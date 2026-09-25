import Foundation
import SwiftData

/// One local behavior row. Analytics never exports the full log.
@Model
final class MealBehaviorEvent {
    var uuid: UUID
    var recipeSlug: String
    var eventTypeRaw: String
    var createdAt: Date
    var planWeekID: UUID?
    var plannedMealID: UUID?
    var replacementReason: String

    init(
        uuid: UUID = UUID(),
        recipeSlug: String,
        eventType: MealBehaviorEventType,
        createdAt: Date = .now,
        planWeekID: UUID? = nil,
        plannedMealID: UUID? = nil,
        replacementReason: String = ""
    ) {
        self.uuid = uuid
        self.recipeSlug = recipeSlug
        self.eventTypeRaw = eventType.rawValue
        self.createdAt = createdAt
        self.planWeekID = planWeekID
        self.plannedMealID = plannedMealID
        self.replacementReason = replacementReason
    }

    var eventType: MealBehaviorEventType {
        MealBehaviorEventType(rawValue: eventTypeRaw) ?? .viewed
    }
}
