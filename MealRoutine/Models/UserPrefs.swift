import Foundation
import SwiftData

/// Single local household profile. There is no account.
@Model
final class UserPrefs {
    /// Default people count. New evenings copy it. A planned meal can override it.
    /// Profile “Porsiyonu kaydet” writes this and stamps the open week’s meals.
    var householdSize: Int
    var eveningsPerWeek: Int
    var maxCookMinutes: Int
    var dislikedIngredientIds: [String]
    var hasCompletedOnboarding: Bool
    var createdAt: Date
    /// Next plan only. The open week is not rebuilt when these change.
    var discoveryLevelRaw: String = DiscoveryLevel.balanced.rawValue
    var repeatPreferenceRaw: String = RepeatPreference.balanced.rawValue
    var difficultyPreferenceRaw: String = DifficultyPreference.mostlyEasy.rawValue
    var weekdayStyleRaw: String = WeekdayStyle.mostlyQuick.rawValue
    var dismissedPatternIDs: [String] = []
    /// V1 feedback is copied into meal memory once, then live events take over.
    var didBackfillMealMemory: Bool = false

    init(
        householdSize: Int = 2,
        eveningsPerWeek: Int = 5,
        maxCookMinutes: Int = CookTimeOptions.defaultMinutes,
        dislikedIngredientIds: [String] = [],
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = .now
    ) {
        self.householdSize = householdSize
        self.eveningsPerWeek = eveningsPerWeek
        self.maxCookMinutes = maxCookMinutes
        self.dislikedIngredientIds = dislikedIngredientIds
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
    }

    var discoveryLevel: DiscoveryLevel {
        get { DiscoveryLevel(rawValue: discoveryLevelRaw) ?? .balanced }
        set { discoveryLevelRaw = newValue.rawValue }
    }

    var repeatPreference: RepeatPreference {
        get { RepeatPreference(rawValue: repeatPreferenceRaw) ?? .balanced }
        set { repeatPreferenceRaw = newValue.rawValue }
    }

    var difficultyPreference: DifficultyPreference {
        get { DifficultyPreference(rawValue: difficultyPreferenceRaw) ?? .mostlyEasy }
        set { difficultyPreferenceRaw = newValue.rawValue }
    }

    var weekdayStyle: WeekdayStyle {
        get { WeekdayStyle(rawValue: weekdayStyleRaw) ?? .mostlyQuick }
        set { weekdayStyleRaw = newValue.rawValue }
    }

    var planningPreferences: PlanningPreferences {
        PlanningPreferences(
            maxCookMinutes: CookTimeOptions.resolved(maxCookMinutes),
            dislikedIngredientIds: Set(dislikedIngredientIds),
            discovery: discoveryLevel,
            repetition: repeatPreference,
            difficulty: difficultyPreference,
            weekdayStyle: weekdayStyle
        )
    }
}
