import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecipeDetailViewModel {
    var isShowingFeedback = false
    var errorMessage: String?
    private var pendingCooked = false

    func markCooked(slug: String, plannedMealUUID: UUID?, in context: ModelContext) {
        do {
            if let plannedMealUUID {
                try WeekPlanService.markCooked(uuid: plannedMealUUID, in: context)
            } else if let week = try WeekPlanService.currentWeek(in: context),
                      let meal = week.meals.first(where: { $0.recipeSlug == slug }) {
                try WeekPlanService.markCooked(uuid: meal.uuid, in: context)
            }
            pendingCooked = true
            isShowingFeedback = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commit(rating: MealRating, slug: String, in context: ModelContext) {
        do {
            try WeekPlanService.recordFeedback(
                slug: slug,
                rating: rating,
                cooked: pendingCooked,
                in: context
            )
            pendingCooked = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
