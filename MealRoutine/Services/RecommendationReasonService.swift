import Foundation

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
        if let memory, memory.lovedCount > 0 {
            return "Bunu daha önce sevmiştin"
        }
        if let similar = similarLovedLabel(for: candidate, profile: profile, bySlug: catalogBySlug) {
            return similar
        }
        if let memory, memory.timesCooked >= 2 {
            return "Bunu birkaç kez pişirmiştin"
        }
        let isNew = isNew(memory)
        if isNew, profile.lovedCategories.contains(normalized(candidate.category)) {
            return "Sevdiğin bir kategoriden yeni bir tarif"
        }
        if isNew, !candidate.protein.isEmpty, profile.lovedProteins.contains(candidate.protein) {
            return "Sevdiğin bir proteinden yeni bir tarif"
        }
        if let memory, memory.wouldMakeAgainCount > 0 {
            return "Bunu yine yapmak istemiştin"
        }
        if let memory, memory.timesCooked > 0 {
            return "Daha önce pişirdiğin bir tarif"
        }
        if isNew, profile.lovedCuisines.contains(normalizedCuisine(candidate.cuisine)) {
            return "Sevdiğin bir mutfaktan yeni bir tarif"
        }
        if let usual = profile.usualCookMinutes, candidate.totalMinutes <= usual + 5 {
            return "Alışık olduğun pişirme süresine uyar"
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
    ) -> String? {
        guard profile.lovedSlugs.contains(where: { $0 != candidate.slug }) else { return nil }
        for slug in profile.lovedSlugs where slug != candidate.slug {
            guard let other = bySlug[slug] else { continue }
            if sharesShape(candidate, other) {
                if let protein = PreferenceInsightBuilder.proteinTitle(candidate.protein), !protein.isEmpty {
                    return "Sevdiğin \(protein) tariflerine benziyor"
                }
                return "Sevdiğin bir tarife benziyor"
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
