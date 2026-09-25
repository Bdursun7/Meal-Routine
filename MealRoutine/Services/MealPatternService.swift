import Foundation

/// Cautious pattern copy. Hidden until three data points exist.
/// Wording stays soft: "gibisin", never "her zaman".
struct MealPattern: Equatable, Identifiable, Sendable {
    var id: String
    var message: String
}

enum MealPatternService {
    static let minimumDataPoints = 3

    static func patterns(
        memories: [String: MealMemorySnapshot],
        candidates: [PickerCandidate],
        dismissed: Set<String> = []
    ) -> [MealPattern] {
        let points = MealMemoryReducer.dataPointCount(in: Array(memories.values))
        guard points >= minimumDataPoints else { return [] }
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [MealPattern] = []

        let cooked = memories.filter { $0.value.timesCooked > 0 }
        let quickCooks = cooked.filter { slug, _ in
            (bySlug[slug]?.totalMinutes ?? 999) <= 30
        }
        if cooked.count >= 3, quickCooks.count * 3 >= cooked.count * 2 {
            found.append(
                MealPattern(
                    id: "quick-meals",
                    message: "30 dakikanın altındaki yemekleri tercih ediyor gibisin."
                )
            )
        }

        let poultryCooks = cooked.reduce(0) { partial, item in
            partial + (bySlug[item.key]?.protein == "poultry" ? item.value.timesCooked : 0)
        }
        if poultryCooks >= 3 {
            found.append(
                MealPattern(
                    id: "poultry-often",
                    message: "Tavuk tariflerini sık pişiriyor gibisin."
                )
            )
        }

        let pastaLoved = memories.filter { slug, memory in
            memory.lovedCount > 0 && isPasta(bySlug[slug])
        }
        if pastaLoved.count >= 3 {
            found.append(
                MealPattern(
                    id: "pasta-loved",
                    message: "\(pastaLoved.count) makarna tarifini sevmiş gibisin."
                )
            )
        }

        return found.filter { !dismissed.contains($0.id) }
    }

    private static func isPasta(_ candidate: PickerCandidate?) -> Bool {
        guard let candidate else { return false }
        let tags = candidate.tags.map { $0.lowercased() }
        if tags.contains("pasta") || tags.contains("makarna") { return true }
        let category = candidate.category.lowercased()
        return category.contains("pasta") || category.contains("makarna")
    }
}
