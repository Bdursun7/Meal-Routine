import Foundation

/// Cautious pattern copy. Hidden until three data points exist.
/// Wording stays soft: "gibisin", never "her zaman".
struct MealPattern: Equatable, Identifiable, Sendable {
    /// Stable id (`quick-meals`, `poultry-often`, `pasta-loved`); dismissals are stored by id.
    var id: String
    var count: Int = 0

    var message: String {
        switch id {
        case "quick-meals":
            return L10n.text("pattern.quickMeals", "30 dakikanın altındaki yemekleri tercih ediyor gibisin.")
        case "poultry-often":
            return L10n.text("pattern.poultryOften", "Tavuk tariflerini sık pişiriyor gibisin.")
        case "pasta-loved":
            return L10n.format("pattern.pastaLoved", "%ld makarna tarifini sevmiş gibisin.", count)
        default:
            return ""
        }
    }
}

enum MealPatternService {
    static let minimumDataPoints = 3

    static func patterns(
        memories: [String: MealMemorySnapshot],
        candidates: [PickerCandidate],
        dismissed: Set<String> = []
    ) -> [MealPattern] {
        patterns(
            memories: memories,
            bySlug: Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first }),
            dismissed: dismissed
        )
    }

    static func patterns(
        memories: [String: MealMemorySnapshot],
        bySlug: [String: PickerCandidate],
        dismissed: Set<String> = []
    ) -> [MealPattern] {
        let points = MealMemoryReducer.dataPointCount(in: Array(memories.values))
        guard points >= minimumDataPoints else { return [] }
        var found: [MealPattern] = []

        let cooked = memories.filter { $0.value.timesCooked > 0 }
        let quickCooks = cooked.filter { slug, _ in
            (bySlug[slug]?.totalMinutes ?? 999) <= 30
        }
        if cooked.count >= 3, quickCooks.count * 3 >= cooked.count * 2 {
            found.append(
                MealPattern(id: "quick-meals")
            )
        }

        let poultryCooks = cooked.reduce(0) { partial, item in
            partial + (bySlug[item.key]?.protein == "poultry" ? item.value.timesCooked : 0)
        }
        if poultryCooks >= 3 {
            found.append(
                MealPattern(id: "poultry-often")
            )
        }

        let pastaLoved = memories.filter { slug, memory in
            memory.lovedCount > 0 && isPasta(bySlug[slug])
        }
        if pastaLoved.count >= 3 {
            found.append(
                MealPattern(id: "pasta-loved", count: pastaLoved.count)
            )
        }

        return found.filter { !dismissed.contains($0.id) }
    }

    /// Catalog tag / category code. Never a display name.
    private static let pastaTag = "pasta"

    private static func isPasta(_ candidate: PickerCandidate?) -> Bool {
        guard let candidate else { return false }
        if candidate.tags.contains(where: { $0.lowercased() == pastaTag }) { return true }
        return candidate.category.lowercased().contains(pastaTag)
    }
}
