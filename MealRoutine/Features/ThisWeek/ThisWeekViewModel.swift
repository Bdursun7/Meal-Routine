import Foundation
import Observation
import SwiftData

struct WeekMealPresentation: Identifiable, Equatable {
    var id: UUID
    var dayTitle: String
    var dateTitle: String
    var recipeName: String
    var minutes: Int
    var servings: Int
    var isCooked: Bool
    var rating: MealRating?
    var slug: String
}

struct WeekSummaryPresentation: Equatable {
    var planned: Int
    var cooked: Int
    var loved: Int
}

@MainActor
@Observable
final class ThisWeekViewModel {
    var alertMessage: String?
    var isWorking = false

    func summary(meals: [WeekMealPresentation]) -> WeekSummaryPresentation {
        WeekSummaryPresentation(
            planned: meals.count,
            cooked: meals.filter(\.isCooked).count,
            loved: meals.filter { $0.rating == .loved }.count
        )
    }

    func meals(
        weeks: [PlanWeek],
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        now: Date = .now
    ) -> [WeekMealPresentation] {
        let start = WeekCalendar.weekStart(containing: now)
        guard let week = weeks.first(where: { WeekCalendar.isSameDay($0.weekStart, start) }) else {
            return []
        }
        let names = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        return week.meals
            .sorted { $0.dayOffset < $1.dayOffset }
            .map { meal in
                let recipe = names[meal.recipeSlug]
                let date = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
                return WeekMealPresentation(
                    id: meal.uuid,
                    dayTitle: WeekCalendar.dayTitle(offset: meal.dayOffset),
                    dateTitle: WeekCalendar.shortDate(date),
                    recipeName: recipe?.displayName ?? meal.recipeSlug,
                    minutes: recipe?.totalMinutes ?? 0,
                    servings: meal.servings,
                    isCooked: meal.cookedAt != nil,
                    rating: ratings[meal.recipeSlug],
                    slug: meal.recipeSlug
                )
            }
    }

    func ensureWeek(in context: ModelContext) {
        do {
            _ = try WeekPlanService.ensureCurrentWeek(in: context)
            try GroceryListService.rebuild(in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func regenerate(in context: ModelContext) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else {
                alertMessage = WeekPlanError.missingPreferences.errorDescription
                return
            }
            let request = WeekPlanService.planRequest(from: prefs)
            _ = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            try GroceryListService.rebuild(in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func replace(mealID: UUID, in context: ModelContext) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try WeekPlanService.replaceMeal(uuid: mealID, in: context)
            try GroceryListService.rebuild(in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
