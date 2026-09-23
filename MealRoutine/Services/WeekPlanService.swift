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

/// Builds and edits the current Monday-start week with `MealRecommender`.
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
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = pickerCandidates(from: recipes, ratings: ratings)
        let recent = recentSightings(meals: meals, feedback: feedback)
        if let existing = try currentWeek(in: context, now: now) {
            // Capture the outgoing plan before the week row (and its meals) is deleted.
            MealExposureLog.record(exposureSightings(in: existing), now: now)
            context.delete(existing)
        }
        let slugs = MealRecommender.pick(
            candidates: candidates,
            evenings: request.evenings,
            maxCookMinutes: request.maxCookMinutes,
            dislikedIngredientIds: request.dislikedIngredientIds,
            recent: recent,
            now: now
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

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = pickerCandidates(from: recipes, ratings: ratings)
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        // The slot being replaced stays an anchor so the new recipe is not a twin of it,
        // and every other evening this week is an anchor too. All of those slugs are blocked.
        var anchors: [PickerCandidate] = []
        var excluding: Set<String> = []
        for planned in week.meals {
            excluding.insert(planned.recipeSlug)
            if let candidate = bySlug[planned.recipeSlug], !anchors.contains(where: { $0.slug == candidate.slug }) {
                anchors.append(candidate)
            }
        }
        excluding.insert(meal.recipeSlug)

        let now = Date()
        let plannedAt = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
        let outgoing = RecentMealSighting(
            slug: meal.recipeSlug,
            at: meal.cookedAt ?? plannedAt,
            wasCooked: meal.cookedAt != nil
        )
        let recent = recentSightings(meals: meals, feedback: feedback)
        guard let slug = MealRecommender.pick(
            candidates: candidates,
            evenings: 1,
            maxCookMinutes: CookTimeOptions.resolved(prefs.maxCookMinutes),
            dislikedIngredientIds: Set(prefs.dislikedIngredientIds),
            excludingSlugs: excluding,
            recent: recent,
            anchoredMeals: anchors,
            now: now
        ).first else {
            throw WeekPlanError.noAlternative
        }

        MealExposureLog.record([outgoing], now: now)
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
            evenings: min(max(prefs.eveningsPerWeek, 1), MealRecommender.eveningCap),
            maxCookMinutes: CookTimeOptions.resolved(prefs.maxCookMinutes),
            dislikedIngredientIds: Set(prefs.dislikedIngredientIds)
        )
    }

    private static func pickerCandidates(
        from recipes: [Recipe],
        ratings: [String: MealRating]
    ) -> [PickerCandidate] {
        recipes.map { recipe in
            let orderedIds = recipe.ingredients
                .sorted { lhs, rhs in
                    if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                    return lhs.ingredientId < rhs.ingredientId
                }
                .map(\.ingredientId)
            let course = recipe.unitoolsCategory.isEmpty ? recipe.category : recipe.unitoolsCategory
            let tags = recipe.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            return PickerCandidate(
                slug: recipe.slug,
                totalMinutes: recipe.totalMinutes,
                trDogfoodScore: recipe.trDogfoodScore,
                ingredientIds: Set(orderedIds),
                rating: ratings[recipe.slug],
                cuisine: recipe.country,
                category: course,
                tags: Set(tags),
                protein: MealRecommender.proteinFamily(in: orderedIds)
            )
        }
    }

    private static func recentSightings(
        meals: [PlannedMeal],
        feedback: [RecipeFeedback]
    ) -> [RecentMealSighting] {
        var sightings: [RecentMealSighting] = []
        for meal in meals {
            if let week = meal.week {
                let plannedAt = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
                sightings.append(
                    RecentMealSighting(
                        slug: meal.recipeSlug,
                        at: meal.cookedAt ?? plannedAt,
                        wasCooked: meal.cookedAt != nil
                    )
                )
            } else if let cookedAt = meal.cookedAt {
                sightings.append(
                    RecentMealSighting(slug: meal.recipeSlug, at: cookedAt, wasCooked: true)
                )
            }
        }
        for item in feedback where item.cooked {
            sightings.append(
                RecentMealSighting(slug: item.recipeSlug, at: item.createdAt, wasCooked: true)
            )
        }
        sightings.append(contentsOf: MealExposureLog.load())
        return sightings
    }

    private static func exposureSightings(in week: PlanWeek) -> [RecentMealSighting] {
        week.meals.map { meal in
            let plannedAt = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
            return RecentMealSighting(
                slug: meal.recipeSlug,
                at: meal.cookedAt ?? plannedAt,
                wasCooked: meal.cookedAt != nil
            )
        }
    }
}
