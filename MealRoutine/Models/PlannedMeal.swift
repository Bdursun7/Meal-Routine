import Foundation
import SwiftData

/// A single evening on the weekly plan. `dayOffset` is days after Monday.
@Model
final class PlannedMeal {
    var uuid: UUID
    var dayOffset: Int
    var slot: String
    var recipeSlug: String
    /// People this evening is cooked and shopped for.
    /// Overrides `UserPrefs.householdSize` for this meal only.
    /// New weeks copy the household size. Profile “Porsiyonu kaydet” copies it again.
    var servings: Int
    var cookedAt: Date?
    var week: PlanWeek? = nil

    init(
        uuid: UUID = UUID(),
        dayOffset: Int,
        slot: String = "evening",
        recipeSlug: String,
        servings: Int,
        cookedAt: Date? = nil
    ) {
        self.uuid = uuid
        self.dayOffset = dayOffset
        self.slot = slot
        self.recipeSlug = recipeSlug
        self.servings = servings
        self.cookedAt = cookedAt
    }
}
