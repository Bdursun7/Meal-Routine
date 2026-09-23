import Foundation
import Observation
import SwiftData

/// Short-lived proof that a rating was written. Shown after the prompt closes.
struct SavedRatingNotice: Equatable, Identifiable {
    var id = UUID()
    var rating: MealRating

    var message: String {
        "Kaydedildi · \(rating.title)"
    }
}

@MainActor
@Observable
final class RecipeDetailViewModel {
    var isShowingRatingPrompt = false
    var errorMessage: String?
    var savedNotice: SavedRatingNotice?
    private var pendingCooked = false
    private var pendingPlannedMealUUID: UUID?
    private var isSavingRating = false

    /// Asks for a rating after cooking. The meal is marked cooked only when a rating is saved,
    /// so cancel writes neither `cookedAt` nor `RecipeFeedback`.
    func markCooked(plannedMealUUID: UUID?) {
        pendingCooked = true
        pendingPlannedMealUUID = plannedMealUUID
        savedNotice = nil
        isShowingRatingPrompt = true
    }

    /// Opens the same prompt to replace an existing rating, without a new cook mark.
    func presentRatingChange() {
        pendingCooked = false
        pendingPlannedMealUUID = nil
        savedNotice = nil
        isShowingRatingPrompt = true
    }

    func cancelRating() {
        pendingCooked = false
        pendingPlannedMealUUID = nil
        isShowingRatingPrompt = false
    }

    func saveRating(rating: MealRating, slug: String, in context: ModelContext) {
        guard isShowingRatingPrompt, !isSavingRating else { return }
        isSavingRating = true
        defer { isSavingRating = false }
        do {
            if pendingCooked {
                try markPendingMealCooked(slug: slug, in: context)
            }
            try WeekPlanService.recordFeedback(
                slug: slug,
                rating: rating,
                cooked: pendingCooked,
                in: context
            )
            pendingCooked = false
            pendingPlannedMealUUID = nil
            isShowingRatingPrompt = false
            savedNotice = SavedRatingNotice(rating: rating)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markPendingMealCooked(slug: String, in context: ModelContext) throws {
        if let pendingPlannedMealUUID {
            try WeekPlanService.markCooked(uuid: pendingPlannedMealUUID, in: context)
        } else if let week = try WeekPlanService.currentWeek(in: context),
                  let meal = week.meals.first(where: { $0.recipeSlug == slug }) {
            try WeekPlanService.markCooked(uuid: meal.uuid, in: context)
        }
    }

    func dismissSavedNotice() {
        savedNotice = nil
    }
}
