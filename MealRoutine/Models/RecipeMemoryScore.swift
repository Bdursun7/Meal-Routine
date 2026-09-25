import Foundation

/// Pieces of one V2 rank. Computed when a plan or a list is built. Not stored.
struct RecipeMemoryScore: Equatable, Sendable {
    var preference: Int
    var behavior: Int
    var variety: Int
    var repetitionPenalty: Int
    var discovery: Int

    var final: Int {
        preference + behavior + variety + discovery - repetitionPenalty
    }

    static let zero = RecipeMemoryScore(
        preference: 0,
        behavior: 0,
        variety: 0,
        repetitionPenalty: 0,
        discovery: 0
    )
}

/// One evening that made it into a generated plan. Explanation text reads these, not a guess.
struct PlannedPick: Equatable, Sendable {
    var slug: String
    var minutes: Int
    var dayOffset: Int
    var isNew: Bool
    var wasLoved: Bool
}

/// Household signals the scorer treats as established. One lone event does not fill these sets.
struct TasteProfile: Equatable, Sendable {
    var lovedCategories: Set<String>
    var lovedProteins: Set<String>
    var lovedCuisines: Set<String>
    var frequentCuisines: Set<String>
    var triedCategories: Set<String>
    var lovedSlugs: Set<String>
    var dataPointCount: Int
    /// Median minutes of recipes cooked at least once. Nil until three cooks exist.
    var usualCookMinutes: Int?

    static let empty = TasteProfile(
        lovedCategories: [],
        lovedProteins: [],
        lovedCuisines: [],
        frequentCuisines: [],
        triedCategories: [],
        lovedSlugs: [],
        dataPointCount: 0,
        usualCookMinutes: nil
    )
}

/// Knobs for the next plan. Defaults match the product locks.
struct PlanningPreferences: Equatable, Sendable {
    var maxCookMinutes: Int
    var dislikedIngredientIds: Set<String>
    var discovery: DiscoveryLevel
    var repetition: RepeatPreference
    var difficulty: DifficultyPreference
    var weekdayStyle: WeekdayStyle

    static func standard(maxCookMinutes: Int, dislikedIngredientIds: Set<String> = []) -> PlanningPreferences {
        PlanningPreferences(
            maxCookMinutes: maxCookMinutes,
            dislikedIngredientIds: dislikedIngredientIds,
            discovery: .balanced,
            repetition: .balanced,
            difficulty: .mostlyEasy,
            weekdayStyle: .mostlyQuick
        )
    }
}
