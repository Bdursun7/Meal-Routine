import Foundation
import SwiftData

enum WeekPlanError: LocalizedError {
    case noAlternative
    case missingPreferences

    var errorDescription: String? {
        switch self {
        case .noAlternative:
            "Bu filtrelere uyan başka tarif kalmadı."
        case .missingPreferences:
            "Tercihler bulunamadı. Profil'den kurulumu tamamla."
        }
    }
}

struct PlanRequest: Sendable {
    var householdSize: Int
    var evenings: Int
    var maxCookMinutes: Int
    var dislikedIngredientIds: Set<String>
}

/// Builds and edits the current Monday-start week with `NaiveMealPicker`.
enum WeekPlanService {
    @MainActor
    static func currentWeek(in context: ModelContext, now: Date = .now) throws -> PlanWeek? {
        let start = WeekCalendar.weekStart(containing: now)
        let weeks = try context.fetch(FetchDescriptor<PlanWeek>())
        return weeks.first { WeekCalendar.isSameDay($0.weekStart, start) }
    }

    @MainActor
    static func ensureCurrentWeek(in context: ModelContext, now: Date = .now) throws -> PlanWeek? {
        if let week = try currentWeek(in: context, now: now) {
            return week
        }
        guard let prefs = try UserPrefsStore.existing(in: context), prefs.hasCompletedOnboarding else {
            return nil
        }
        return try replaceCurrentWeek(in: context, request: planRequest(from: prefs), now: now)
    }

    @MainActor
    static func replaceCurrentWeek(
        in context: ModelContext,
        request: PlanRequest,
        now: Date = .now
    ) throws -> PlanWeek {
        if let existing = try currentWeek(in: context, now: now) {
            context.delete(existing)
        }

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = recipes.map { recipe in
            PickerCandidate(
                slug: recipe.slug,
                totalMinutes: recipe.totalMinutes,
                trDogfoodScore: recipe.trDogfoodScore,
                ingredientIds: recipe.ingredientIDs,
                rating: ratings[recipe.slug]
            )
        }
        let slugs = NaiveMealPicker.pick(
            candidates: candidates,
            evenings: request.evenings,
            maxCookMinutes: request.maxCookMinutes,
            dislikedIngredientIds: request.dislikedIngredientIds
        )

        let week = PlanWeek(
            weekStart: WeekCalendar.weekStart(containing: now),
            householdSize: request.householdSize
        )
        context.insert(week)

        for (offset, slug) in slugs.enumerated() {
            let meal = PlannedMeal(
                dayOffset: offset,
                recipeSlug: slug,
                servings: request.householdSize
            )
            context.insert(meal)
            meal.week = week
        }
        try context.save()
        return week
    }

    @MainActor
    static func replaceMeal(uuid: UUID, in context: ModelContext) throws {
        guard let prefs = try UserPrefsStore.existing(in: context) else {
            throw WeekPlanError.missingPreferences
        }
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == uuid }), let week = meal.week else {
            throw WeekPlanError.noAlternative
        }

        var excluding = Set(week.meals.map(\.recipeSlug))
        excluding.insert(meal.recipeSlug)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = recipes.map { recipe in
            PickerCandidate(
                slug: recipe.slug,
                totalMinutes: recipe.totalMinutes,
                trDogfoodScore: recipe.trDogfoodScore,
                ingredientIds: recipe.ingredientIDs,
                rating: ratings[recipe.slug]
            )
        }
        guard let slug = NaiveMealPicker.pick(
            candidates: candidates,
            evenings: 1,
            maxCookMinutes: CookTimeOptions.resolved(prefs.maxCookMinutes),
            dislikedIngredientIds: Set(prefs.dislikedIngredientIds),
            excludingSlugs: excluding
        ).first else {
            throw WeekPlanError.noAlternative
        }

        meal.recipeSlug = slug
        meal.cookedAt = nil
        try context.save()
    }

    @MainActor
    static func markCooked(uuid: UUID, in context: ModelContext, at date: Date = .now) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == uuid }) else { return }
        if meal.cookedAt == nil {
            meal.cookedAt = date
            try context.save()
        }
    }

    @MainActor
    static func recordFeedback(
        slug: String,
        rating: MealRating,
        cooked: Bool,
        in context: ModelContext
    ) throws {
        let feedback = RecipeFeedback(recipeSlug: slug, rating: rating, cooked: cooked)
        context.insert(feedback)
        try context.save()
    }

    static func planRequest(from prefs: UserPrefs) -> PlanRequest {
        PlanRequest(
            householdSize: HouseholdSizeLimits.clamped(prefs.householdSize),
            evenings: min(max(prefs.eveningsPerWeek, 1), NaiveMealPicker.eveningCap),
            maxCookMinutes: CookTimeOptions.resolved(prefs.maxCookMinutes),
            dislikedIngredientIds: Set(prefs.dislikedIngredientIds)
        )
    }
}
