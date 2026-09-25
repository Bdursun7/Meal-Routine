import Foundation
import SwiftData

/// Reads and writes the local meal-memory rows. Does not touch the recipe catalog.
@MainActor
enum MealMemoryService {
    static func snapshots(in context: ModelContext) throws -> [String: MealMemorySnapshot] {
        let rows = try context.fetch(FetchDescriptor<MealMemory>())
        return Dictionary(rows.map { ($0.recipeSlug, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
    }

    static func upsert(_ snapshot: MealMemorySnapshot, in context: ModelContext) throws {
        let slug = snapshot.recipeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return }
        var stored = snapshot
        stored.recipeID = slug
        let rows = try context.fetch(FetchDescriptor<MealMemory>())
        if let existing = rows.first(where: { $0.recipeSlug == slug }) {
            existing.replace(with: stored)
        } else {
            context.insert(MealMemory(snapshot: stored))
        }
    }

    /// Imports V1 feedback once. Later cooks and ratings go through behavior tracking.
    static func backfillIfNeeded(in context: ModelContext) throws {
        guard let prefs = try UserPrefsStore.existing(in: context), !prefs.didBackfillMealMemory else { return }
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let seeds = feedback.map { item in
            FeedbackSeed(
                slug: item.recipeSlug,
                rating: item.rating,
                cooked: item.cooked,
                createdAt: item.createdAt,
                reasons: item.reasons
            )
        }
        let built = MealMemoryBackfill.snapshots(feedback: seeds, sightings: MealExposureLog.load())
        for snapshot in built.values {
            try upsert(snapshot, in: context)
        }
        prefs.didBackfillMealMemory = true
        try context.save()
    }

    /// Drops learned history. Onboarding prefs and the open week stay.
    static func reset(in context: ModelContext) throws {
        let memories = try context.fetch(FetchDescriptor<MealMemory>())
        for row in memories { context.delete(row) }
        let events = try context.fetch(FetchDescriptor<MealBehaviorEvent>())
        for row in events { context.delete(row) }
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        for row in feedback { context.delete(row) }
        if let prefs = try UserPrefsStore.existing(in: context) {
            prefs.dismissedPatternIDs = []
            prefs.didBackfillMealMemory = true
        }
        try context.save()
        UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
        Analytics.track(.mealMemoryReset)
    }
}
