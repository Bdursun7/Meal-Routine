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
}
