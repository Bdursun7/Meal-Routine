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
    var portionStatusMessage: String?
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
            Analytics.track(.recipeRated)
            Analytics.track(.mealFeedbackGiven)
            if rating == .loved {
                Analytics.track(.recipeLoved)
            } else if rating == .never {
                Analytics.track(.recipeDisliked)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loved is the favorite list. Adding one does not require a new cook.
    func toggleFavorite(isLoved: Bool, slug: String, in context: ModelContext) {
        do {
            try WeekPlanService.setFavorite(slug: slug, loved: !isLoved, in: context)
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

    /// Persists the stepper count for this screen.
    /// A planned evening overrides only that meal. Otherwise the household default
    /// is locked and copied onto every evening of the open week.
    func savePortions(servings: Int, mealUUID: UUID?, in context: ModelContext) {
        let count = HouseholdSizeLimits.clamped(servings)
        errorMessage = nil
        do {
            if let mealUUID {
                try PortionSaveService.saveMealServings(count, mealUUID: mealUUID, in: context)
                portionStatusMessage = "Bu akşam \(count) kişilik kaydedildi. Market listesi güncellendi."
            } else {
                try PortionSaveService.saveHouseholdSize(count, in: context)
                portionStatusMessage = "Ev halkı \(count) kişilik kaydedildi. Bu haftanın akşamları ve market listesi güncellendi."
            }
        } catch {
            portionStatusMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}
