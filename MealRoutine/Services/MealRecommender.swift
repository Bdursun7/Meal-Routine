import Foundation

/// One catalog row reduced to the fields the recommender ranks on.
struct PickerCandidate: Equatable, Sendable {
    var slug: String
    var totalMinutes: Int
    var trDogfoodScore: Int
    var ingredientIds: Set<String>
    var rating: MealRating?
    /// Country code from the catalog (`TR`, `GR`, …). Exact repeats are a strong diversity hit.
    var cuisine: String
    /// Course used for variety. V1 passes `unitoolsCategory` because `Recipe.category` is always dinner.
    var category: String
    var tags: Set<String>
    /// Primary protein family (`poultry`, `red-meat`, `seafood`, `egg`, `legume`, `tofu`, `dairy`).
    /// Empty when no mapped ingredient is present, and empty does not count as a repeat.
    var protein: String
    /// Catalog diet tags (`vegetarian`, `vegan`, …). Empty when the recipe lists none.
    var diets: Set<String> = []
    /// Catalog difficulty (`easy`, `medium`, `hard`). Empty skips the V2 difficulty gate.
    var difficulty: String = ""
}

/// A cook or a plan that should pull this recipe down for a while.
struct RecentMealSighting: Equatable, Sendable {
    var slug: String
    var at: Date
    var wasCooked: Bool
}

/// Pieces of one candidate's rank. Higher `total` is better.
struct MealRankBreakdown: Equatable, Sendable {
    var curation: Int
    var lovedBoost: Int
    var recencyPenalty: Int
    var diversityPenalty: Int

    var total: Int {
        curation + lovedBoost - recencyPenalty - diversityPenalty
    }
}

/// Deterministic V1 ranker. No network and no randomness.
///
/// Pipeline, in order:
/// 1. Hard filter: cook time, disliked ingredients, Never-again, and slugs already blocked.
/// 2. Preference score: the curated `trDogfoodScore` already on the recipe.
/// 3. Recent-meal penalty from cooks and plans inside `recencyWindowDays`.
/// 4. Diversity against meals already on this week (and meals picked earlier in this fill).
/// 5. Loved is a score boost on top of curation, not a separate sort that ignores penalties.
///
/// The week is filled greedily: each pick is the best remaining slug, then it becomes an
/// anchor so the next evening pays for repeating it. Ties break on ascending slug.
enum MealRecommender {
    /// Keep equal to `EveningCountOptions.maximum`. The onboarding chips use that list.
    static let eveningCap = 5
    static let recencyWindowDays = 21
    static let secondsPerDay = 86_400

    /// Covers the current catalog gap (scores run 41...91) so a loved recipe still
    /// outranks an unloved one before recency or diversity. A just-cooked loved meal
    /// can still lose, because the cooked penalty is larger than this boost.
    static let lovedBoost = 56
    /// Full penalty for a meal planned today. Falls to zero at `recencyWindowDays`.
    static let plannedPenaltyCap = 62
    /// Cooked meals are remembered harder than a plan that never made it to the pan.
    static let cookedPenaltyCap = 78

    /// One repeat of the same country. A second strong dish from that country can still
    /// win when the course and protein differ; a third pays this twice and usually drops out.
    static let sameCuisinePenalty = 18
    static let similarCuisinePenalty = 10
    static let sameCategoryPenalty = 8
    static let sameProteinPenalty = 18
    /// Per shared tag. Catalog tags are style, format, starch, and heat
    /// (`Tools/recipe_tags.py`). Cuisine and protein are separate fields.
    static let sharedTagPenalty = 14
    /// Stops a long anchor list from flattening every candidate to the same floor.
    static let diversityPenaltyCap = 140

    static func pick(
        candidates: [PickerCandidate],
        evenings: Int,
        maxCookMinutes: Int,
        dislikedIngredientIds: Set<String>,
        excludingSlugs: Set<String> = [],
        recent: [RecentMealSighting] = [],
        anchoredMeals: [PickerCandidate] = [],
        now: Date = .now
    ) -> [String] {
        let limit = min(max(evenings, 0), eveningCap)
        guard limit > 0 else { return [] }

        var blocked = excludingSlugs
        for meal in anchoredMeals {
            blocked.insert(meal.slug)
        }

        var remaining = candidates.filter { candidate in
            passesFilters(
                candidate,
                maxCookMinutes: maxCookMinutes,
                dislikedIngredientIds: dislikedIngredientIds,
                blockedSlugs: blocked
            )
        }
        var anchors = anchoredMeals
        var chosen: [String] = []

        while chosen.count < limit {
            let ranked = remaining.sorted { lhs, rhs in
                let left = breakdown(for: lhs, recent: recent, anchoredMeals: anchors, now: now).total
                let right = breakdown(for: rhs, recent: recent, anchoredMeals: anchors, now: now).total
                if left != right { return left > right }
                return lhs.slug < rhs.slug
            }
            guard let next = ranked.first else { break }
            chosen.append(next.slug)
            anchors.append(next)
            remaining.removeAll { $0.slug == next.slug }
        }
        return chosen
    }

    static func breakdown(
        for candidate: PickerCandidate,
        recent: [RecentMealSighting] = [],
        anchoredMeals: [PickerCandidate] = [],
        now: Date = .now
    ) -> MealRankBreakdown {
        let loved = candidate.rating == .loved ? lovedBoost : 0
        return MealRankBreakdown(
            curation: candidate.trDogfoodScore,
            lovedBoost: loved,
            recencyPenalty: recencyPenalty(for: candidate.slug, recent: recent, now: now),
            diversityPenalty: diversityPenalty(for: candidate, anchoredMeals: anchoredMeals)
        )
    }

    static func passesFilters(
        _ candidate: PickerCandidate,
        maxCookMinutes: Int,
        dislikedIngredientIds: Set<String>,
        blockedSlugs: Set<String> = []
    ) -> Bool {
        candidate.totalMinutes <= maxCookMinutes
            && !blockedSlugs.contains(candidate.slug)
            && candidate.rating != .never
            && candidate.ingredientIds.isDisjoint(with: dislikedIngredientIds)
    }

    static func recencyPenalty(
        for slug: String,
        recent: [RecentMealSighting],
        now: Date
    ) -> Int {
        let window = recencyWindowDays * secondsPerDay
        var best = 0
        for sighting in recent where sighting.slug == slug {
            let age = Int(now.timeIntervalSince(sighting.at).rounded(.down))
            let cap = sighting.wasCooked ? cookedPenaltyCap : plannedPenaltyCap
            let penalty = scaledPenalty(cap: cap, ageSeconds: age, windowSeconds: window)
            if penalty > best { best = penalty }
        }
        return best
    }

    /// Linear fade: full `cap` at age <= 0, zero at or past the window. Integer rounding.
    static func scaledPenalty(cap: Int, ageSeconds: Int, windowSeconds: Int) -> Int {
        if windowSeconds <= 0 { return 0 }
        if ageSeconds <= 0 { return cap }
        if ageSeconds >= windowSeconds { return 0 }
        let remaining = windowSeconds - ageSeconds
        return (cap * remaining + windowSeconds / 2) / windowSeconds
    }

    static func diversityPenalty(
        for candidate: PickerCandidate,
        anchoredMeals: [PickerCandidate]
    ) -> Int {
        var total = 0
        let candidateRegion = cuisineRegion(for: candidate.cuisine)
        let candidateTags = normalizedTags(candidate.tags)
        for anchor in anchoredMeals {
            if sameToken(candidate.cuisine, anchor.cuisine) {
                total += sameCuisinePenalty
            } else {
                let anchorRegion = cuisineRegion(for: anchor.cuisine)
                if !candidateRegion.isEmpty, candidateRegion == anchorRegion {
                    total += similarCuisinePenalty
                }
            }
            if sameToken(candidate.category, anchor.category) {
                total += sameCategoryPenalty
            }
            if !candidate.protein.isEmpty, candidate.protein == anchor.protein {
                total += sameProteinPenalty
            }
            let shared = candidateTags.intersection(normalizedTags(anchor.tags))
            total += shared.count * sharedTagPenalty
        }
        return min(total, diversityPenaltyCap)
    }

    /// First mapped ingredient in list order wins, so the protein the recipe leads with
    /// is the one the week tries not to repeat. Condiment ids are intentionally absent.
    static func proteinFamily(in ingredientIdsInOrder: [String]) -> String {
        for raw in ingredientIdsInOrder {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let family = ingredientFamilies[id] {
                return family
            }
        }
        return ""
    }

    /// Coarse cuisine bucket. Unknown codes only match an identical country, not a region.
    static func cuisineRegion(for countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cuisineRegions[code] ?? ""
    }

    private static func normalizedTags(_ tags: Set<String>) -> Set<String> {
        Set(
            tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static func sameToken(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    private static let ingredientFamilies: [String: String] = [
        "chicken": "poultry",

        "beef": "red-meat",
        "lamb": "red-meat",
        "pork": "red-meat",
        "porkbelly": "red-meat",
        "leanbeef": "red-meat",
        "veal": "red-meat",
        "bacon": "red-meat",
        "ham": "red-meat",
        "sausage": "red-meat",
        "merguez": "red-meat",
        "guanciale": "red-meat",
        "prosciutto": "red-meat",
        "chourico": "red-meat",
        "chinesesausage": "red-meat",
        "ribs": "red-meat",
        "rabbit": "red-meat",
        "sucuk": "red-meat",
        "pastirma": "red-meat",
        "liver": "red-meat",
        "tripe": "red-meat",

        "fish": "seafood",
        "salmon": "seafood",
        "tuna": "seafood",
        "trout": "seafood",
        "prawns": "seafood",
        "mussels": "seafood",
        "cod": "seafood",
        "codfish": "seafood",
        "cuttlefish": "seafood",
        "sardines": "seafood",
        "crab": "seafood",
        "cockles": "seafood",
        "clams": "seafood",
        "barramundi": "seafood",
        "hilsa": "seafood",
        "anchovy": "seafood",
        "mackerel": "seafood",
        "seabass": "seafood",

        "egg": "egg",
        "eggs": "egg",
        "eggwhite": "egg",
        "yolks": "egg",

        "lentils": "legume",
        "chickpeas": "legume",
        "beans": "legume",
        "broadbeans": "legume",
        "butterbeans": "legume",
        "soybeans": "legume",
        "moongdal": "legume",

        "tofu": "tofu",

        "paneer": "dairy",
        "halloumi": "dairy",
        "cheese": "dairy",
        "feta": "dairy",
        "parmesan": "dairy",
        "curdcheese": "dairy",
        "brynza": "dairy",
        "gruyere": "dairy",
        "pecorino": "dairy",
        "mozzarella": "dairy",
        "brinedcheese": "dairy",
        "qurut": "dairy",
        "vacherin": "dairy",
        "kajmak": "dairy",
        "curd": "dairy",
        "yogurt": "dairy",
        "yoghurt": "dairy",
        "matsun": "dairy",
        "kefir": "dairy",
        "ayib": "dairy",
    ]

    private static let cuisineRegions: [String: String] = [
        "TR": "mediterranean",
        "GR": "mediterranean",
        "IT": "mediterranean",
        "ES": "mediterranean",
        "PT": "mediterranean",
        "FR": "mediterranean",
        "CY": "mediterranean",
        "HR": "mediterranean",

        "BG": "balkan",
        "RS": "balkan",
        "AL": "balkan",
        "MK": "balkan",
        "ME": "balkan",

        "LB": "mena",
        "JO": "mena",
        "SY": "mena",
        "EG": "mena",
        "TN": "mena",
        "DZ": "mena",
        "IL": "mena",
        "OM": "mena",
        "IR": "mena",

        "IN": "south-asia",
        "PK": "south-asia",
        "LK": "south-asia",
        "BD": "south-asia",
        "NP": "south-asia",
        "BT": "south-asia",
        "MV": "south-asia",

        "CN": "east-asia",
        "JP": "east-asia",
        "KR": "east-asia",

        "TH": "southeast-asia",
        "ID": "southeast-asia",
        "MY": "southeast-asia",
        "SG": "southeast-asia",
        "PH": "southeast-asia",
        "KH": "southeast-asia",

        "GE": "caucasus",
        "AM": "caucasus",
        "TJ": "caucasus",

        "GB": "western-europe",
        "DE": "western-europe",
        "AT": "western-europe",
        "CH": "western-europe",
        "BE": "western-europe",
        "NL": "western-europe",
        "DK": "northern-europe",
        "SE": "northern-europe",
        "FI": "northern-europe",
        "IS": "northern-europe",

        "RU": "eastern-europe",
        "BY": "eastern-europe",
        "PL": "eastern-europe",
        "CZ": "eastern-europe",
        "SK": "eastern-europe",
        "LT": "eastern-europe",

        "PE": "latin-america",
        "UY": "latin-america",
        "MX": "latin-america",
        "BO": "latin-america",
        "EC": "latin-america",
        "CR": "latin-america",

        "ET": "east-africa",
        "TZ": "east-africa",
        "MZ": "east-africa",
        "CI": "west-africa",
        "CM": "west-africa",
        "CD": "central-africa",
        "ZA": "southern-africa",

        "US": "north-america",
        "AU": "oceania",
    ]
}
