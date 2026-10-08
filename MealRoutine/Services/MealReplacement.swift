import Foundation

/// Quick filters on the single-evening replace sheet.
enum ReplacementChip: String, CaseIterable, Identifiable, Sendable {
    case faster
    case similarLoved
    case different
    case loved
    case tryNew
    case noChicken
    case vegetarian
    case usual
    case surprise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faster: L10n.text("replace.chip.faster", "Daha hızlı")
        case .similarLoved: L10n.text("replace.chip.similarLoved", "Sevdiğime benzer")
        case .different: L10n.text("replace.chip.different", "Tamamen farklı")
        case .loved: L10n.text("replace.chip.loved", "Bir favori kullan")
        case .tryNew: L10n.text("replace.chip.tryNew", "Yeni bir tarif")
        case .noChicken: L10n.text("replace.chip.noChicken", "Tavuksuz")
        case .vegetarian: L10n.text("replace.chip.vegetarian", "Vejetaryen")
        case .usual: L10n.text("replace.chip.usual", "Alıştığım gibi")
        case .surprise: L10n.text("replace.chip.surprise", "Sürpriz")
        }
    }
}

/// Optional meal-memory context. Empty keeps the V1 ranker so existing checks stay put.
struct ReplacementMemory: Equatable, Sendable {
    var memories: [String: MealMemorySnapshot] = [:]
    var preferences: PlanningPreferences?
    var dayOffset: Int = 0
    var now: Date = .now
}

/// Why an alternative is offered, as a code. `text` is the display sentence.
enum ReplacementReason: Equatable, Hashable, Sendable {
    case surprise
    case faster
    case likeLovedMeal
    case likeLovedRecipe
    case untried
    case usualStyle
    case differentProtein
    case fitsTimeLimit
    case fitsTonight
    case personal(RecommendationReason)

    var text: String {
        switch self {
        case .surprise: return L10n.text("replace.reason.surprise", "Sürpriz bir alternatif")
        case .faster: return L10n.text("replace.reason.faster", "Daha kısa sürer")
        case .likeLovedMeal: return L10n.text("replace.reason.likeLovedMeal", "Sevdiğin bir yemeğe benziyor")
        case .likeLovedRecipe: return L10n.text("reason.similarToLoved", "Sevdiğin bir tarife benziyor")
        case .untried: return L10n.text("replace.reason.untried", "Henüz denemediğin bir tarif")
        case .usualStyle: return L10n.text("replace.reason.usualStyle", "Alışık olduğun tarza yakın")
        case .differentProtein: return L10n.text("replace.reason.differentProtein", "Çeşit için farklı bir protein")
        case .fitsTimeLimit: return L10n.text("replace.reason.fitsTimeLimit", "Süre sınırına uyar")
        case .fitsTonight: return L10n.text("replace.reason.fitsTonight", "Bu akşam için uygun")
        case .personal(let reason): return reason.text
        }
    }
}

struct ReplacementChoice: Equatable, Sendable, Identifiable {
    var slug: String
    var minutes: Int
    var reasonCode: ReplacementReason

    var id: String { slug }
    var reason: String { reasonCode.text }
}

/// Filters the recommender's candidate list for one evening.
/// Never-again, cook-time cap, disliked ingredients, and blocked slugs stay hard filters.
/// Surprise is one deterministic pick, not `Random`.
enum MealReplacement {
    static let listLimit = 8

    static func toggled(_ chips: Set<ReplacementChip>, _ chip: ReplacementChip) -> Set<ReplacementChip> {
        if chip == .surprise {
            return chips.contains(.surprise) ? [] : [.surprise]
        }
        var next = chips
        next.remove(.surprise)
        if next.contains(chip) {
            next.remove(chip)
        } else {
            next.insert(chip)
        }
        return next
    }

    static func choices(
        catalog: [PickerCandidate],
        current: PickerCandidate,
        blockedSlugs: Set<String>,
        maxCookMinutes: Int,
        dislikedIngredientIds: Set<String>,
        activeChips: Set<ReplacementChip>,
        anchors: [PickerCandidate] = [],
        memory: ReplacementMemory = ReplacementMemory()
    ) -> [ReplacementChoice] {
        var blocked = blockedSlugs
        blocked.insert(current.slug)
        let preferences = memory.preferences ?? PlanningPreferences.standard(
            maxCookMinutes: maxCookMinutes,
            dislikedIngredientIds: dislikedIngredientIds
        )
        let useMemory = memory.preferences != nil || !memory.memories.isEmpty
        // Score each recipe once. Doing it inside `sorted` rebuilt the taste profile
        // on every comparison, which is quadratic on a 325-recipe catalog.
        let bySlug = Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let taste = PersonalizedScoringService.profile(memories: memory.memories, bySlug: bySlug)
        let loved = catalog.filter { other in
            other.rating == .loved || (memory.memories[other.slug]?.lovedCount ?? 0) > 0
        }
        let eligible = catalog.filter { candidate in
            let passes = useMemory
                ? PersonalizedScoringService.isEligible(
                    candidate,
                    preferences: preferences,
                    memory: memory.memories[candidate.slug],
                    blockedSlugs: blocked,
                    enforceLovedGap: !activeChips.contains(.loved),
                    enforceDifficulty: true,
                    now: memory.now
                )
                : MealRecommender.passesFilters(
                    candidate,
                    maxCookMinutes: maxCookMinutes,
                    dislikedIngredientIds: dislikedIngredientIds,
                    blockedSlugs: blocked
                )
            return passes && matches(
                candidate,
                current: current,
                chips: activeChips,
                taste: taste,
                loved: loved,
                memory: memory
            )
        }
        let ranked = eligible.map { candidate in
            (
                candidate,
                rankValue(
                    candidate,
                    anchors: anchors,
                    memory: memory,
                    preferences: preferences,
                    taste: taste,
                    bySlug: bySlug,
                    useMemory: useMemory
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.slug < rhs.0.slug
        }
        .map(\.0)
        guard !ranked.isEmpty else { return [] }
        if activeChips.contains(.surprise) {
            let pick = surprisePick(in: ranked, currentSlug: current.slug)
            return [choice(for: pick, current: current, maxCookMinutes: maxCookMinutes, chips: activeChips, memory: memory, taste: taste, bySlug: bySlug)]
        }
        return ranked.prefix(listLimit).map {
            choice(for: $0, current: current, maxCookMinutes: maxCookMinutes, chips: activeChips, memory: memory, taste: taste, bySlug: bySlug)
        }
    }

    static func isChicken(_ candidate: PickerCandidate) -> Bool {
        if candidate.protein == "poultry" { return true }
        return candidate.ingredientIds.contains { $0.caseInsensitiveCompare("chicken") == .orderedSame }
    }

    static func isVegetarian(_ candidate: PickerCandidate) -> Bool {
        let diets = Set(candidate.diets.map { $0.lowercased() })
        return diets.contains("vegetarian") || diets.contains("vegan")
    }

    /// A different protein when the current meal has one. Otherwise a different cuisine or course.
    static func isDifferent(_ candidate: PickerCandidate, from current: PickerCandidate) -> Bool {
        if !current.protein.isEmpty {
            return candidate.protein != current.protein
        }
        return !sameToken(candidate.cuisine, current.cuisine)
            || !sameToken(candidate.category, current.category)
    }

    static func reason(
        for candidate: PickerCandidate,
        current: PickerCandidate,
        maxCookMinutes: Int,
        chips: Set<ReplacementChip>
    ) -> String {
        reasonCode(for: candidate, current: current, maxCookMinutes: maxCookMinutes, chips: chips).text
    }

    static func reasonCode(
        for candidate: PickerCandidate,
        current: PickerCandidate,
        maxCookMinutes: Int,
        chips: Set<ReplacementChip>
    ) -> ReplacementReason {
        if chips.contains(.surprise) {
            return .surprise
        }
        if chips.contains(.faster), candidate.totalMinutes < current.totalMinutes {
            return .faster
        }
        if candidate.rating == .loved || chips.contains(.loved) {
            return .likeLovedMeal
        }
        if chips.contains(.similarLoved) {
            return .likeLovedRecipe
        }
        if chips.contains(.tryNew) {
            return .untried
        }
        if chips.contains(.usual) {
            return .usualStyle
        }
        if !current.protein.isEmpty, candidate.protein != current.protein {
            return .differentProtein
        }
        if candidate.totalMinutes <= maxCookMinutes {
            return .fitsTimeLimit
        }
        return .fitsTonight
    }

    private static func matches(
        _ candidate: PickerCandidate,
        current: PickerCandidate,
        chips: Set<ReplacementChip>,
        taste: TasteProfile,
        loved: [PickerCandidate],
        memory: ReplacementMemory
    ) -> Bool {
        if chips.contains(.surprise) { return true }
        if chips.contains(.faster), candidate.totalMinutes >= current.totalMinutes {
            return false
        }
        if chips.contains(.different), !isDifferent(candidate, from: current) {
            return false
        }
        if chips.contains(.noChicken), isChicken(candidate) {
            return false
        }
        if chips.contains(.vegetarian), !isVegetarian(candidate) {
            return false
        }
        if chips.contains(.loved), candidate.rating != .loved, memory.memories[candidate.slug]?.isFavorite != true {
            return false
        }
        if chips.contains(.similarLoved), !isSimilarToLoved(candidate, loved: loved) {
            return false
        }
        if chips.contains(.tryNew), !isUntouched(candidate, memory: memory) {
            return false
        }
        if chips.contains(.usual), !isUsual(candidate, taste: taste) {
            return false
        }
        return true
    }

    private static func rankValue(
        _ candidate: PickerCandidate,
        anchors: [PickerCandidate],
        memory: ReplacementMemory,
        preferences: PlanningPreferences,
        taste: TasteProfile,
        bySlug: [String: PickerCandidate],
        useMemory: Bool
    ) -> Int {
        guard useMemory else {
            return MealRecommender.breakdown(for: candidate, anchoredMeals: anchors).total
        }
        return PersonalizedScoringService.listRank(
            candidate,
            memory: memory.memories[candidate.slug],
            taste: taste,
            catalogBySlug: bySlug,
            preferences: preferences,
            anchors: anchors,
            dayOffset: memory.dayOffset,
            now: memory.now
        )
    }

    private static func isSimilarToLoved(
        _ candidate: PickerCandidate,
        loved: [PickerCandidate]
    ) -> Bool {
        if loved.isEmpty { return candidate.rating == .loved }
        return loved.contains { other in
            other.slug != candidate.slug && sharesShape(candidate, other)
        }
    }

    private static func isUntouched(_ candidate: PickerCandidate, memory: ReplacementMemory) -> Bool {
        if candidate.rating != nil { return false }
        return RecommendationReasonService.isNew(memory.memories[candidate.slug])
    }

    private static func isUsual(
        _ candidate: PickerCandidate,
        taste: TasteProfile
    ) -> Bool {
        let established = !taste.lovedProteins.isEmpty || !taste.lovedCategories.isEmpty || !taste.lovedSlugs.isEmpty
        if !established { return true }
        if candidate.rating == .loved || taste.lovedSlugs.contains(candidate.slug) { return true }
        if !candidate.protein.isEmpty, taste.lovedProteins.contains(candidate.protein) { return true }
        let category = candidate.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return taste.lovedCategories.contains(category)
    }

    private static func sharesShape(_ lhs: PickerCandidate, _ rhs: PickerCandidate) -> Bool {
        if !lhs.protein.isEmpty, lhs.protein == rhs.protein { return true }
        let left = lhs.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !left.isEmpty, left.caseInsensitiveCompare(right) == .orderedSame { return true }
        return !lhs.tags.isEmpty && !lhs.tags.isDisjoint(with: rhs.tags)
    }

    private static func surprisePick(in ranked: [PickerCandidate], currentSlug: String) -> PickerCandidate {
        let index = stableIndex(currentSlug, count: ranked.count)
        let pick = ranked[index]
        if ranked.count > 1, pick.slug == ranked[0].slug {
            return ranked[1]
        }
        return pick
    }

    static func stableIndex(_ slug: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = slug.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return sum % count
    }

    private static func choice(
        for candidate: PickerCandidate,
        current: PickerCandidate,
        maxCookMinutes: Int,
        chips: Set<ReplacementChip>,
        memory: ReplacementMemory,
        taste: TasteProfile,
        bySlug: [String: PickerCandidate]
    ) -> ReplacementChoice {
        var code = reasonCode(for: candidate, current: current, maxCookMinutes: maxCookMinutes, chips: chips)
        if memory.preferences != nil || !memory.memories.isEmpty,
           !chips.contains(.surprise),
           !chips.contains(.faster) {
            if let personal = RecommendationReasonService.personalReasonCode(
                for: candidate,
                memory: memory.memories[candidate.slug],
                profile: taste,
                catalogBySlug: bySlug
            ) {
                code = .personal(personal)
            }
        }
        return ReplacementChoice(
            slug: candidate.slug,
            minutes: candidate.totalMinutes,
            reasonCode: code
        )
    }

    private static func sameToken(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
