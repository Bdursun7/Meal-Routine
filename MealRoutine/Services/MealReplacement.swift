import Foundation

/// Quick filters on the single-evening replace sheet.
enum ReplacementChip: String, CaseIterable, Identifiable, Sendable {
    case faster
    case different
    case noChicken
    case vegetarian
    case loved
    case surprise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faster: "Daha hızlı"
        case .different: "Farklı bir şey"
        case .noChicken: "Tavuksuz"
        case .vegetarian: "Vejetaryen"
        case .loved: "Sevdiklerimden"
        case .surprise: "Sürpriz"
        }
    }
}

struct ReplacementChoice: Equatable, Sendable, Identifiable {
    var slug: String
    var minutes: Int
    var reason: String

    var id: String { slug }
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
        anchors: [PickerCandidate] = []
    ) -> [ReplacementChoice] {
        var blocked = blockedSlugs
        blocked.insert(current.slug)
        let eligible = catalog.filter { candidate in
            MealRecommender.passesFilters(
                candidate,
                maxCookMinutes: maxCookMinutes,
                dislikedIngredientIds: dislikedIngredientIds,
                blockedSlugs: blocked
            ) && matches(candidate, current: current, chips: activeChips)
        }
        let ranked = eligible.sorted { lhs, rhs in
            let left = MealRecommender.breakdown(for: lhs, anchoredMeals: anchors).total
            let right = MealRecommender.breakdown(for: rhs, anchoredMeals: anchors).total
            if left != right { return left > right }
            return lhs.slug < rhs.slug
        }
        guard !ranked.isEmpty else { return [] }
        if activeChips.contains(.surprise) {
            let pick = surprisePick(in: ranked, currentSlug: current.slug)
            return [choice(for: pick, current: current, maxCookMinutes: maxCookMinutes, chips: activeChips)]
        }
        return ranked.prefix(listLimit).map {
            choice(for: $0, current: current, maxCookMinutes: maxCookMinutes, chips: activeChips)
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
        if chips.contains(.surprise) {
            return "Sürpriz bir alternatif"
        }
        if chips.contains(.faster), candidate.totalMinutes < current.totalMinutes {
            return "Daha kısa sürer"
        }
        if candidate.rating == .loved {
            return "Sevdiğin bir yemeğe benziyor"
        }
        if !current.protein.isEmpty, candidate.protein != current.protein {
            return "Çeşit için farklı bir protein"
        }
        if candidate.totalMinutes <= maxCookMinutes {
            return "Süre sınırına uyar"
        }
        return "Bu akşam için uygun"
    }

    private static func matches(
        _ candidate: PickerCandidate,
        current: PickerCandidate,
        chips: Set<ReplacementChip>
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
        if chips.contains(.loved), candidate.rating != .loved {
            return false
        }
        return true
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
        chips: Set<ReplacementChip>
    ) -> ReplacementChoice {
        ReplacementChoice(
            slug: candidate.slug,
            minutes: candidate.totalMinutes,
            reason: reason(for: candidate, current: current, maxCookMinutes: maxCookMinutes, chips: chips)
        )
    }

    private static func sameToken(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
