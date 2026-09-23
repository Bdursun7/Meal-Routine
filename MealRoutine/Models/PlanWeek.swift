import Foundation
import SwiftData

/// One Monday-start week of evening meals.
@Model
final class PlanWeek {
    var uuid: UUID
    var weekStart: Date
    var createdAt: Date
    var householdSize: Int

    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.week)
    var meals: [PlannedMeal] = []

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.week)
    var groceries: [GroceryItem] = []

    init(
        uuid: UUID = UUID(),
        weekStart: Date,
        createdAt: Date = .now,
        householdSize: Int
    ) {
        self.uuid = uuid
        self.weekStart = weekStart
        self.createdAt = createdAt
        self.householdSize = householdSize
    }
}
