import Foundation
@testable import MealRoutine

enum TestFixtures {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func candidate(
        _ slug: String,
        score: Int = 60,
        minutes: Int = 40,
        cuisine: String = "TR",
        category: String = "main",
        protein: String = "",
        tags: Set<String> = [],
        ingredients: Set<String> = [],
        diets: Set<String> = [],
        rating: MealRating? = nil,
        difficulty: String = "easy"
    ) -> PickerCandidate {
        PickerCandidate(
            slug: slug,
            totalMinutes: minutes,
            trDogfoodScore: score,
            ingredientIds: ingredients,
            rating: rating,
            cuisine: cuisine,
            category: category,
            tags: tags,
            protein: protein,
            diets: diets,
            difficulty: difficulty
        )
    }

    static func prefs(
        minutes: Int = 60,
        discovery: DiscoveryLevel = .balanced,
        repetition: RepeatPreference = .balanced,
        difficulty: DifficultyPreference = .mostlyEasy,
        weekday: WeekdayStyle = .mostlyQuick
    ) -> PlanningPreferences {
        PlanningPreferences(
            maxCookMinutes: minutes,
            dislikedIngredientIds: [],
            discovery: discovery,
            repetition: repetition,
            difficulty: difficulty,
            weekdayStyle: weekday
        )
    }

    static func replacementMemory(
        _ memories: [String: MealMemorySnapshot] = [:]
    ) -> ReplacementMemory {
        ReplacementMemory(
            memories: memories,
            preferences: prefs(),
            dayOffset: 0,
            now: now
        )
    }
}
