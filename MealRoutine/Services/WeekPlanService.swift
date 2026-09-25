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
        try MealMemoryService.backfillIfNeeded(in: context)
        return try replaceCurrentWeek(in: context, request: planRequest(from: prefs), now: now)
    }

    @MainActor
    static func replaceCurrentWeek(
        in context: ModelContext,
        request: PlanRequest,
        now: Date = .now
    ) throws -> PlanWeek {
        try MealMemoryService.backfillIfNeeded(in: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = pickerCandidates(from: recipes, ratings: ratings)
        let recent = recentSightings(meals: meals, feedback: feedback)
        var memories = try MealMemoryService.snapshots(in: context)
        overlayRecency(recent, onto: &memories)
        let prefs = try UserPrefsStore.existing(in: context)
        if let existing = try currentWeek(in: context, now: now) {
            // Capture the outgoing plan before the week row (and its meals) is deleted.
            MealExposureLog.record(exposureSightings(in: existing), now: now)
            let retiredMealIDs = Set(existing.meals.map(\.uuid))
            let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
            for check in checks {
                guard let mealUUID = check.mealUUID, retiredMealIDs.contains(mealUUID) else { continue }
                context.delete(check)
            }
            for meal in existing.meals {
                context.delete(meal)
            }
            for item in existing.groceries {
                context.delete(item)
            }
            context.delete(existing)
            // Commit the delete before inserting the new week. One transaction can
            // leave the old cooked meals attached to the replacement week.
            try context.save()
        }
        let preferences = prefs?.planningPreferences ?? PlanningPreferences.standard(
            maxCookMinutes: request.maxCookMinutes,
            dislikedIngredientIds: request.dislikedIngredientIds
        )
        let selection = PersonalizedScoringService.select(
            candidates: candidates,
            evenings: request.evenings,
            preferences: preferences,
            memories: memories,
            now: now
        )
        let slugs = selection.slugs

        let week = PlanWeek(
            weekStart: WeekCalendar.weekStart(containing: now),
            householdSize: request.householdSize
        )
        week.explanation = selection.explanation
        context.insert(week)

        for (offset, slug) in slugs.enumerated() {
            let meal = PlannedMeal(
                dayOffset: offset,
                recipeSlug: slug,
                servings: request.householdSize,
                cookedAt: nil
            )
            context.insert(meal)
            meal.cookedAt = nil
            meal.week = week
            try BehaviorTrackingService.record(
                .selected,
                recipeSlug: slug,
                at: now,
                planWeekID: week.uuid,
                plannedMealID: meal.uuid,
                in: context,
                saves: false
            )
        }
        try context.save()
        if !slugs.isEmpty {
            Analytics.track(.planGenerated)
        }
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
        let memories = try MealMemoryService.snapshots(in: context)
        let selection = PersonalizedScoringService.select(
            candidates: candidates,
            evenings: 1,
            preferences: prefs.planningPreferences,
            memories: memories,
            blockedSlugs: excluding,
            initialAnchors: anchors,
            startDayOffset: meal.dayOffset,
            now: now
        )
        guard let slug = selection.slugs.first else {
            throw WeekPlanError.noAlternative
        }

        try replaceMeal(uuid: uuid, with: slug, in: context)
    }

    /// Swaps one evening for a chosen slug. Other evenings stay. Grocery rebuild is the caller's job.
    @MainActor
    static func replaceMeal(
        uuid: UUID,
        with slug: String,
        reason: String = "",
        in context: ModelContext
    ) throws {
        guard let prefs = try UserPrefsStore.existing(in: context) else {
            throw WeekPlanError.missingPreferences
        }
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == uuid }), let week = meal.week else {
            throw WeekPlanError.noAlternative
        }
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meal.recipeSlug else {
            throw WeekPlanError.noAlternative
        }
        if week.meals.contains(where: { $0.uuid != meal.uuid && $0.recipeSlug == trimmed }) {
            throw WeekPlanError.noAlternative
        }

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        guard let recipe = recipes.first(where: { $0.slug == trimmed }) else {
            throw WeekPlanError.noAlternative
        }
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        guard let candidate = pickerCandidates(from: [recipe], ratings: ratings).first,
              MealRecommender.passesFilters(
                candidate,
                maxCookMinutes: CookTimeOptions.resolved(prefs.maxCookMinutes),
                dislikedIngredientIds: Set(prefs.dislikedIngredientIds),
                blockedSlugs: []
              ) else {
            throw WeekPlanError.noAlternative
        }

        let plannedAt = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
        let outgoing = RecentMealSighting(
            slug: meal.recipeSlug,
            at: meal.cookedAt ?? plannedAt,
            wasCooked: meal.cookedAt != nil
        )
        MealExposureLog.record([outgoing], now: Date())
        let replacedSlug = meal.recipeSlug
        try BehaviorTrackingService.record(
            .replaced,
            recipeSlug: replacedSlug,
            planWeekID: week.uuid,
            plannedMealID: meal.uuid,
            replacementReason: reason,
            in: context,
            saves: false
        )
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        for check in checks where check.mealUUID == meal.uuid {
            context.delete(check)
        }
        meal.recipeSlug = trimmed
        meal.cookedAt = nil
        meal.skippedAt = nil
        try BehaviorTrackingService.record(
            .selected,
            recipeSlug: trimmed,
            planWeekID: week.uuid,
            plannedMealID: meal.uuid,
            replacementReason: reason,
            in: context,
            saves: false
        )
        try context.save()
        Analytics.track(.mealReplaced)
    }

    /// Records a skip without changing the recipe or the grocery list.
    @MainActor
    static func markSkipped(uuid: UUID, in context: ModelContext, at date: Date = .now) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == uuid }) else { return }
        if meal.cookedAt != nil || meal.skippedAt != nil { return }
        meal.skippedAt = date
        try BehaviorTrackingService.record(
            .skipped,
            recipeSlug: meal.recipeSlug,
            at: date,
            planWeekID: meal.week?.uuid,
            plannedMealID: meal.uuid,
            in: context,
            saves: false
        )
        try context.save()
    }

    @MainActor
    static func markCooked(uuid: UUID, in context: ModelContext, at date: Date = .now) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == uuid }) else { return }
        if meal.cookedAt == nil {
            meal.cookedAt = date
            meal.skippedAt = nil
            try BehaviorTrackingService.record(
                .cooked,
                recipeSlug: meal.recipeSlug,
                at: date,
                planWeekID: meal.week?.uuid,
                plannedMealID: meal.uuid,
                in: context,
                saves: false
            )
            try context.save()
            Analytics.track(.mealCooked)
        }
    }

    /// Loved is the favorite. Clearing it writes a newer Okay rating and does not mark a cook.
    @MainActor
    static func setFavorite(slug: String, loved: Bool, in context: ModelContext) throws {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let rating: MealRating = loved ? .loved : .okay
        try recordFeedback(slug: trimmed, rating: rating, cooked: false, in: context)
        try BehaviorTrackingService.setFavorite(recipeSlug: trimmed, isFavorite: loved, in: context)
        Analytics.track(.recipeRated)
        if loved {
            Analytics.track(.recipeLoved)
        }
    }

    @MainActor
    static func recordFeedback(
        slug: String,
        rating: MealRating,
        cooked: Bool,
        reasons: [FeedbackReason] = [],
        in context: ModelContext
    ) throws {
        let feedback = RecipeFeedback(
            recipeSlug: slug,
            rating: rating,
            cooked: cooked,
            reasons: reasons
        )
        context.insert(feedback)
        let event: MealBehaviorEventType
        switch rating {
        case .loved: event = .loved
        case .okay: event = .okay
        case .never: event = .neverAgain
        }
        try BehaviorTrackingService.record(
            event,
            recipeSlug: slug,
            reasons: reasons,
            in: context,
            saves: false
        )
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

    static func pickerCandidates(
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
                protein: MealRecommender.proteinFamily(in: orderedIds),
                diets: Set(recipe.diets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
                difficulty: recipe.difficulty
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

    /// Keeps just-retired plans in the repetition penalty without writing a fake cook.
    private static func overlayRecency(
        _ sightings: [RecentMealSighting],
        onto memories: inout [String: MealMemorySnapshot]
    ) {
        for sighting in sightings {
            let slug = sighting.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { continue }
            var snapshot = memories[slug] ?? MealMemorySnapshot(recipeID: slug)
            if snapshot.lastSelectedAt == nil || sighting.at > snapshot.lastSelectedAt! {
                snapshot.lastSelectedAt = sighting.at
            }
            if sighting.wasCooked {
                if snapshot.lastCookedAt == nil || sighting.at > snapshot.lastCookedAt! {
                    snapshot.lastCookedAt = sighting.at
                }
            }
            memories[slug] = snapshot
        }
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
