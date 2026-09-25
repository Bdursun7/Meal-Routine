import Foundation
import SwiftData

/// Writes one behavior event and folds it into that recipe's meal memory.
@MainActor
enum BehaviorTrackingService {
    @discardableResult
    static func record(
        _ event: MealBehaviorEventType,
        recipeSlug: String,
        at date: Date = .now,
        reasons: [FeedbackReason] = [],
        planWeekID: UUID? = nil,
        plannedMealID: UUID? = nil,
        replacementReason: String = "",
        in context: ModelContext,
        saves: Bool = true
    ) throws -> MealMemorySnapshot {
        let slug = recipeSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            return MealMemorySnapshot(recipeID: "")
        }
        let rows = try context.fetch(FetchDescriptor<MealMemory>())
        let existing = rows.first { $0.recipeSlug == slug }
        var snapshot = existing?.snapshot ?? MealMemorySnapshot(recipeID: slug)
        let cookedBefore = snapshot.timesCooked
        let wasNew = RecommendationReasonService.isNew(snapshot)
        MealMemoryReducer.apply(event: event, at: date, reasons: reasons, to: &snapshot)
        if let existing {
            existing.replace(with: snapshot, updatedAt: date)
        } else {
            context.insert(MealMemory(snapshot: snapshot, updatedAt: date))
        }
        context.insert(
            MealBehaviorEvent(
                recipeSlug: slug,
                eventType: event,
                createdAt: date,
                planWeekID: planWeekID,
                plannedMealID: plannedMealID,
                replacementReason: replacementReason
            )
        )
        if saves {
            try context.save()
        }
        Analytics.track(.mealMemoryUpdated, properties: ["kind": event.rawValue])
        if event == .cooked {
            if wasNew && cookedBefore == 0 {
                Analytics.track(.newRecipeCooked)
            } else {
                Analytics.track(.familiarRecipeCooked)
            }
        }
        return snapshot
    }

    static func setFavorite(
        recipeSlug: String,
        isFavorite: Bool,
        in context: ModelContext
    ) throws {
        let slug = recipeSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return }
        let rows = try context.fetch(FetchDescriptor<MealMemory>())
        var snapshot = rows.first { $0.recipeSlug == slug }?.snapshot ?? MealMemorySnapshot(recipeID: slug)
        MealMemoryReducer.setFavorite(isFavorite, on: &snapshot)
        if let existing = rows.first(where: { $0.recipeSlug == slug }) {
            existing.replace(with: snapshot)
        } else {
            context.insert(MealMemory(snapshot: snapshot))
        }
        if isFavorite {
            context.insert(MealBehaviorEvent(recipeSlug: slug, eventType: .favorited))
            Analytics.track(.mealMemoryUpdated, properties: ["kind": MealBehaviorEventType.favorited.rawValue])
        }
        try context.save()
    }
}
