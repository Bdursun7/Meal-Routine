import Foundation
import SwiftData

/// One Monday-start week of evening meals.
@Model
final class PlanWeek {
    var uuid: UUID
    var weekStart: Date
    var createdAt: Date
    var householdSize: Int
    /// Turkish sentence written by V2–V5.0 builds. Read only as a fallback for weeks that have no
    /// `explanationCode`; V5.1+ writes the code instead.
    var explanation: String = ""
    /// `PlanExplanation.code` (language-independent). Empty for weeks written before V5.1.
    var explanationCode: String = ""

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

    var summary: PlanExplanation? {
        PlanExplanation(code: explanationCode)
    }

    func setSummary(_ summary: PlanExplanation) {
        explanationCode = summary.code
        explanation = ""
    }

    /// The plan note in the display language.
    var displayExplanation: String {
        summary?.text ?? explanation
    }
}
