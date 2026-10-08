import Foundation

/// Why a recipe is suggested, as a language-independent code. `text` is the display sentence.
enum RecommendationReason: Equatable, Hashable, Sendable {
    case lovedBefore
    /// `protein` is the catalog protein family code (`poultry`, …); empty when unknown.
    case similarToLoved(protein: String)
    case cookedSeveralTimes
    case newFromLovedCategory
    case newFromLovedProtein
    case wouldMakeAgain
    case cookedBefore
    case newFromLovedCuisine
    case fitsUsualTime

    var text: String {
        switch self {
        case .lovedBefore:
            return L10n.text("reason.lovedBefore", "Bunu daha önce sevmiştin")
        case .similarToLoved(let protein):
            if let title = PreferenceInsightBuilder.proteinTitle(protein), !title.isEmpty {
                return L10n.format("reason.similarToLovedProtein", "Sevdiğin %@ tariflerine benziyor", title)
            }
            return L10n.text("reason.similarToLoved", "Sevdiğin bir tarife benziyor")
        case .cookedSeveralTimes:
            return L10n.text("reason.cookedSeveralTimes", "Bunu birkaç kez pişirmiştin")
        case .newFromLovedCategory:
            return L10n.text("reason.newFromLovedCategory", "Sevdiğin bir kategoriden yeni bir tarif")
        case .newFromLovedProtein:
            return L10n.text("reason.newFromLovedProtein", "Sevdiğin bir proteinden yeni bir tarif")
        case .wouldMakeAgain:
            return L10n.text("reason.wouldMakeAgain", "Bunu yine yapmak istemiştin")
        case .cookedBefore:
            return L10n.text("reason.cookedBefore", "Daha önce pişirdiğin bir tarif")
        case .newFromLovedCuisine:
            return L10n.text("reason.newFromLovedCuisine", "Sevdiğin bir mutfaktan yeni bir tarif")
        case .fitsUsualTime:
            return L10n.text("reason.fitsUsualTime", "Alışık olduğun pişirme süresine uyar")
        }
    }
}

/// One honest sentence for a recipe. Generic time copy is not treated as personal.
enum RecommendationReasonService {
    static func personalReason(
        for candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        profile: TasteProfile,
        catalog: [PickerCandidate]
    ) -> String? {
        personalReason(
            for: candidate,
            memory: memory,
            profile: profile,
            catalogBySlug: Dictionary(catalog.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// `catalogBySlug` is built once for the screen. The array overload rebuilds it per call.
    static func personalReason(
        for candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        profile: TasteProfile,
        catalogBySlug: [String: PickerCandidate]
    ) -> String? {
        personalReasonCode(for: candidate, memory: memory, profile: profile, catalogBySlug: catalogBySlug)?.text
    }

    static func personalReasonCode(
        for candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        profile: TasteProfile,
        catalogBySlug: [String: PickerCandidate]
    ) -> RecommendationReason? {
        if let memory, memory.lovedCount > 0 {
            return .lovedBefore
        }
        if let similar = similarLovedLabel(for: candidate, profile: profile, bySlug: catalogBySlug) {
            return similar
        }
        if let memory, memory.timesCooked >= 2 {
            return .cookedSeveralTimes
        }
        let isNew = isNew(memory)
        if isNew, profile.lovedCategories.contains(normalized(candidate.category)) {
            return .newFromLovedCategory
        }
        if isNew, !candidate.protein.isEmpty, profile.lovedProteins.contains(candidate.protein) {
            return .newFromLovedProtein
        }
        if let memory, memory.wouldMakeAgainCount > 0 {
            return .wouldMakeAgain
        }
        if let memory, memory.timesCooked > 0 {
            return .cookedBefore
        }
        if isNew, profile.lovedCuisines.contains(normalizedCuisine(candidate.cuisine)) {
            return .newFromLovedCuisine
        }
        if let usual = profile.usualCookMinutes, candidate.totalMinutes <= usual + 5 {
            return .fitsUsualTime
        }
        return nil
    }

    static func badge(
        for memory: MealMemorySnapshot?,
        hasHistory: Bool
    ) -> FamiliarityBadge? {
        guard hasHistory else { return nil }
        if let memory, memory.timesCooked > 0 || memory.lovedCount > 0 || memory.isFavorite {
            return .familiar
        }
        if memory == nil || (memory?.timesCooked == 0 && memory?.lovedCount == 0 && memory?.isFavorite != true) {
            return .new
        }
        return nil
    }

    static func isNew(_ memory: MealMemorySnapshot?) -> Bool {
        guard let memory else { return true }
        return memory.timesCooked == 0 && memory.lovedCount == 0 && !memory.isFavorite
    }

    private static func similarLovedLabel(
        for candidate: PickerCandidate,
        profile: TasteProfile,
        bySlug: [String: PickerCandidate]
    ) -> RecommendationReason? {
        guard profile.lovedSlugs.contains(where: { $0 != candidate.slug }) else { return nil }
        for slug in profile.lovedSlugs where slug != candidate.slug {
            guard let other = bySlug[slug] else { continue }
            if sharesShape(candidate, other) {
                return .similarToLoved(protein: candidate.protein)
            }
        }
        return nil
    }

    private static func sharesShape(_ lhs: PickerCandidate, _ rhs: PickerCandidate) -> Bool {
        if !lhs.protein.isEmpty, lhs.protein == rhs.protein { return true }
        if same(lhs.category, rhs.category) { return true }
        return !lhs.tags.isDisjoint(with: rhs.tags) && !lhs.tags.isEmpty
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedCuisine(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
