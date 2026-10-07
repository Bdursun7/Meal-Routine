import Foundation
import SwiftData

enum WeekPlanError: LocalizedError {
    case noAlternative
    case missingPreferences
        case notPlannable
        case alreadyPlanned
        case noOpenEvening
        case sharedWeek

    var errorDescription: String? {
        switch self {
        case .noAlternative:
            "Bu filtrelere uyan başka tarif kalmadı."
        case .missingPreferences:
            "Tercihler bulunamadı. Profil'den kurulumu tamamla."
        case .notPlannable:
            "Bu tarif plana eklenemiyor. Ad, malzeme veya yapılış eksik olabilir; ya da bir daha asla işaretli."
        case .alreadyPlanned:
            "Bu tarif bu haftada zaten var."
        case .noOpenEvening:
            "Bu haftanın açık akşamı kalmadı. Pişirilmiş akşamların üzerine yazılmaz."
        case .sharedWeek:
            "Bu hafta ortak plan. Kişisel plan onun üzerine yazılmaz."
        }
    }
}

/// Cooked evenings stay put. New slugs fill only the open offsets, in order.
enum PlannerLock {
    struct Slot: Equatable, Sendable {
        var dayOffset: Int
        var slug: String
    }

    static func openCount(lockedOffsets: Set<Int>, evenings: Int) -> Int {
        let span = min(max(evenings, 0), MealRecommender.eveningCap)
        let locked = lockedOffsets.filter { (0..<span).contains($0) }.count
        return max(0, span - locked)
    }

    static func merge(locked: [Slot], filled: [String], evenings: Int) -> [Slot] {
        let span = min(max(evenings, 0), MealRecommender.eveningCap)
        let lockedByOffset = Dictionary(locked.map { ($0.dayOffset, $0) }, uniquingKeysWith: { first, _ in first })
        var filledIndex = 0
        var result: [Slot] = []
        for offset in 0..<span {
            if let kept = lockedByOffset[offset] {
                result.append(kept)
            } else if filledIndex < filled.count {
                result.append(Slot(dayOffset: offset, slug: filled[filledIndex]))
                filledIndex += 1
            }
        }
        return result.sorted { $0.dayOffset < $1.dayOffset }
    }
}

struct PlanRequest: Sendable {
    var householdSize: Int
    var evenings: Int
    var maxCookMinutes: Int
    var dislikedIngredientIds: Set<String>
}

/// Builds and edits the current Monday-start week with `PersonalizedScoringService`.
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
        if HouseholdSession.shared.isHouseholdMode {
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
        if HouseholdSession.shared.isHouseholdMode {
            throw WeekPlanError.sharedWeek
        }
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
        let preferences = prefs?.planningPreferences ?? PlanningPreferences.standard(
            maxCookMinutes: request.maxCookMinutes,
            dislikedIngredientIds: request.dislikedIngredientIds
        )
        let existing = try currentWeek(in: context, now: now)
        let lockedMeals = existing?.meals.filter { $0.cookedAt != nil } ?? []
        if lockedMeals.isEmpty {
            return try insertFreshWeek(
                in: context,
                request: request,
                existing: existing,
                candidates: candidates,
                preferences: preferences,
                memories: memories,
                now: now
            )
        }
        guard let existing else {
            return try insertFreshWeek(
                in: context,
                request: request,
                existing: nil,
                candidates: candidates,
                preferences: preferences,
                memories: memories,
                now: now
            )
        }
        return try refillAroundLockedMeals(
            existing,
            in: context,
            request: request,
            lockedMeals: lockedMeals,
            candidates: candidates,
            preferences: preferences,
            memories: memories,
            now: now
        )
    }

    @MainActor
    private static func insertFreshWeek(
        in context: ModelContext,
        request: PlanRequest,
        existing: PlanWeek?,
        candidates: [PickerCandidate],
        preferences: PlanningPreferences,
        memories: [String: MealMemorySnapshot],
        now: Date
    ) throws -> PlanWeek {
        if let existing {
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
        let selection = PersonalizedScoringService.select(
            candidates: candidates,
            evenings: request.evenings,
            preferences: preferences,
            memories: memories,
            pantryStock: pantryStock(in: context),
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
            try insertPlannedMeal(
                slug: slug,
                dayOffset: offset,
                servings: request.householdSize,
                week: week,
                now: now,
                in: context
            )
        }
        try context.save()
        if !slugs.isEmpty {
            Analytics.track(.planGenerated)
        }
        return week
    }

    @MainActor
    private static func pantryStock(in context: ModelContext) -> [PantryPlanningStock] {
        let householdID = HouseholdSession.shared.snapshot.household?.id
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        return items.filter { $0.householdID == householdID && $0.quantity > 0 }.map(\.planningStock)
    }

    /// Keeps cooked evenings and their checks. Skipped evenings are open and can change.
    @MainActor
    private static func refillAroundLockedMeals(
        _ existing: PlanWeek,
        in context: ModelContext,
        request: PlanRequest,
        lockedMeals: [PlannedMeal],
        candidates: [PickerCandidate],
        preferences: PlanningPreferences,
        memories: [String: MealMemorySnapshot],
        now: Date
    ) throws -> PlanWeek {
        let span = min(max(request.evenings, 0), MealRecommender.eveningCap)
        let lockedOffsets = Set(lockedMeals.map(\.dayOffset)).filter { (0..<span).contains($0) }
        let openOffsets = (0..<span).filter { !lockedOffsets.contains($0) }
        let retiring = existing.meals.filter { $0.cookedAt == nil }
        MealExposureLog.record(retiring.map { meal in
            RecentMealSighting(
                slug: meal.recipeSlug,
                at: WeekCalendar.date(weekStart: existing.weekStart, dayOffset: meal.dayOffset),
                wasCooked: false
            )
        }, now: now)
        let retiringIDs = Set(retiring.map(\.uuid))
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        for check in checks {
            guard let mealUUID = check.mealUUID, retiringIDs.contains(mealUUID) else { continue }
            context.delete(check)
        }
        for meal in retiring {
            context.delete(meal)
        }
        for item in existing.groceries where !item.isManual {
            context.delete(item)
        }

        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var blocked = Set(lockedMeals.map(\.recipeSlug))
        var anchors = lockedMeals.compactMap { bySlug[$0.recipeSlug] }
        var filled: [String] = []
        if !openOffsets.isEmpty {
            for offset in openOffsets {
                let selection = PersonalizedScoringService.select(
                    candidates: candidates,
                    evenings: 1,
                    preferences: preferences,
                    memories: memories,
                    blockedSlugs: blocked,
                    initialAnchors: anchors,
                    startDayOffset: offset,
                    now: now
                )
                guard let slug = selection.slugs.first else { break }
                filled.append(slug)
                blocked.insert(slug)
                if let candidate = bySlug[slug] {
                    anchors.append(candidate)
                }
            }
        }
        let slots = PlannerLock.merge(
            locked: lockedMeals.map { PlannerLock.Slot(dayOffset: $0.dayOffset, slug: $0.recipeSlug) },
            filled: filled,
            evenings: request.evenings
        )
        let lockedIdentity = Set(lockedMeals.map { "\($0.dayOffset)|\($0.recipeSlug)" })
        for slot in slots where !lockedIdentity.contains("\(slot.dayOffset)|\(slot.slug)") {
            try insertPlannedMeal(
                slug: slot.slug,
                dayOffset: slot.dayOffset,
                servings: request.householdSize,
                week: existing,
                now: now,
                in: context
            )
        }
        existing.householdSize = request.householdSize
        existing.explanation = weekExplanation(
            slots: slots,
            filledNew: filled.count,
            openCount: openOffsets.count,
            requested: span,
            candidates: candidates,
            memories: memories
        )
        try context.save()
        if !filled.isEmpty {
            Analytics.track(.planGenerated)
        }
        return existing
    }

    @MainActor
    private static func insertPlannedMeal(
        slug: String,
        dayOffset: Int,
        servings: Int,
        week: PlanWeek,
        now: Date,
        in context: ModelContext
    ) throws {
        let meal = PlannedMeal(
            dayOffset: dayOffset,
            recipeSlug: slug,
            servings: servings,
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

    private static func weekExplanation(
        slots: [PlannerLock.Slot],
        filledNew: Int,
        openCount: Int,
        requested: Int,
        candidates: [PickerCandidate],
        memories: [String: MealMemorySnapshot]
    ) -> String {
        if openCount == 0 {
            return PlanExplanationBuilder.lockedMeals
        }
        if filledNew == 0 {
            return PlanExplanationBuilder.emptyPool
        }
        if filledNew < openCount {
            return PlanExplanationBuilder.shortPool(filled: slots.count, requested: requested)
        }
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let taste = PersonalizedScoringService.profile(memories: memories, candidates: candidates)
        let picks = slots.map { slot in
            let memory = memories[slot.slug]
            return PlannedPick(
                slug: slot.slug,
                minutes: bySlug[slot.slug]?.totalMinutes ?? 0,
                dayOffset: slot.dayOffset,
                isNew: RecommendationReasonService.isNew(memory),
                wasLoved: (memory?.lovedCount ?? 0) > 0
            )
        }
        return PlanExplanationBuilder.explain(picks: picks, hasBehavior: taste.dataPointCount > 0)
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

    /// Swaps one evening for a chosen slug. Other evenings stay. The grocery list is rebuilt.
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
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context)
    }

    /// Puts one saved import on the current week because the cook chose it.
    /// Automatic planning still skips unknown time, never-again, and disliked ingredients.
    @MainActor
    static func placeImportedRecipe(slug: String, in context: ModelContext, now: Date = .now) throws {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        guard let recipe = recipes.first(where: { $0.slug == trimmed }),
              ImportedRecipeEligibility.allowsPlanning(recipe) else {
            throw WeekPlanError.notPlannable
        }
        guard let prefs = try UserPrefsStore.existing(in: context) else {
            throw WeekPlanError.missingPreferences
        }
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        if FeedbackIndex.latestRatings(in: feedback)[trimmed] == .never {
            throw WeekPlanError.notPlannable
        }
        let memories = try MealMemoryService.snapshots(in: context)
        if memories[trimmed]?.neverAgain == true {
            throw WeekPlanError.notPlannable
        }
        if !recipe.ingredientIDs.isDisjoint(with: Set(prefs.dislikedIngredientIds)) {
            throw WeekPlanError.notPlannable
        }
        guard let week = try ensureCurrentWeek(in: context, now: now) else {
            throw WeekPlanError.missingPreferences
        }
        if week.meals.contains(where: { $0.recipeSlug == trimmed }) {
            throw WeekPlanError.alreadyPlanned
        }
        let today = WeekCalendar.dayOffset(for: now, weekStart: week.weekStart)
        let ordered = week.meals.sorted { $0.dayOffset < $1.dayOffset }
        let open = ordered.filter { $0.cookedAt == nil }
        guard let meal = open.first(where: { $0.dayOffset == today }) ?? open.first else {
            throw WeekPlanError.noOpenEvening
        }
        let plannedAt = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
        MealExposureLog.record([
            RecentMealSighting(slug: meal.recipeSlug, at: plannedAt, wasCooked: false),
        ], now: now)
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        for check in checks where check.mealUUID == meal.uuid {
            context.delete(check)
        }
        meal.recipeSlug = trimmed
        meal.titleSnapshot = recipe.displayName
        meal.cookedAt = nil
        meal.skippedAt = nil
        try BehaviorTrackingService.record(
            .selected,
            recipeSlug: trimmed,
            at: now,
            planWeekID: week.uuid,
            plannedMealID: meal.uuid,
            in: context,
            saves: false
        )
        try context.save()
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)
        trackPersonalPlan(slug: trimmed, in: context)
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
        recipes.compactMap { recipe in
            guard ImportedRecipeEligibility.allowsPlanning(recipe) else { return nil }
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
                difficulty: recipe.difficulty,
                timeIsUnknown: recipe.timeIsUnknown,
                importInterest: false
            )
        }
    }

    @MainActor
    private static func trackPersonalPlan(slug: String, in context: ModelContext) {
        guard let recipe = try? context.fetch(FetchDescriptor<Recipe>()).first(where: { $0.slug == slug }),
              !recipe.isBundledCatalog else { return }
        Analytics.track(.recipeAddedToPlan, properties: [
            "origin": recipe.origin.rawValue,
            "platform": recipe.sourcePlatform?.rawValue ?? "unknown",
            "state": recipe.collectionState.rawValue,
        ])
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

/// One pass over the catalog's ingredient graph, reused by every tab.
///
/// `TabView` keeps all four roots alive, and each of them used to call
/// `pickerCandidates` from `body`. That faults every recipe's ingredients on the
/// main actor during the tab animation. Ingredients are replaced only when the
/// bundled catalog is re-imported, so the index is keyed by recipe identity and
/// the stored fields the ranker reads. A later body pass with the same key does
/// not touch the relationship again.
struct CatalogIndex: Equatable, Sendable {
    var key: Int
    var candidates: [PickerCandidate]
    /// Slug lookup built with the index. Callers must not rebuild this per row.
    var bySlug: [String: PickerCandidate]
    var displayNames: [String: String]
    var ingredientNames: [String: String]
    /// Ingredient names plus import source fields, built with the index.
    /// The recipe list must not walk `recipe.ingredients` again while the tab appears.
    var searchBlobs: [String: String] = [:]
}

@MainActor
enum CatalogIndexCache {
    private struct Base {
        var key: Int
        var candidates: [PickerCandidate]
        var displayNames: [String: String]
        var ingredientNames: [String: String]
        var searchBlobs: [String: String]
    }

    private static var base: Base?
    /// Unrated index. Returned without copying when a caller does not apply ratings.
    private static var unratedIndex: CatalogIndex?
    /// Last ratings overlay. A later body pass with the same ratings does not copy 325 candidates.
    private static var overlaidKey: Int?
    private static var overlaidIndex: CatalogIndex?

    static func invalidate() {
        base = nil
        unratedIndex = nil
        overlaidKey = nil
        overlaidIndex = nil
    }

    /// Builds the index while the launch spinner is up, before the first tab frame.
    static func warm(in context: ModelContext) throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
        _ = warm(recipes: recipes, ratings: FeedbackIndex.latestRatings(in: feedback))
    }

    static func warm(recipes: [Recipe], ratings: [String: MealRating]) -> CatalogIndex {
        ensureBase(recipes)
        return publish(ratings: ratings)
    }

    /// The index already built by a screen that has the full catalog.
    /// Detail screens fetch one recipe and must not replace this with that row.
    static func current(ratings: [String: MealRating]) -> CatalogIndex? {
        guard base != nil else { return nil }
        return publish(ratings: ratings)
    }

    /// Last index, including ratings applied by the most recent full warm.
    /// A detail screen that only fetched one recipe uses this instead of rebuilding.
    static func cachedIndex() -> CatalogIndex? {
        overlaidIndex ?? unratedIndex
    }

    private static func ensureBase(_ recipes: [Recipe]) {
        let key = recipeKey(recipes)
        if let base, base.key == key {
            return
        }
        let unrated = WeekPlanService.pickerCandidates(from: recipes, ratings: [:])
        var displayNames: [String: String] = [:]
        var ingredientNames: [String: String] = [:]
        var searchBlobs: [String: String] = [:]
        displayNames.reserveCapacity(recipes.count)
        searchBlobs.reserveCapacity(recipes.count)
        for recipe in recipes {
            displayNames[recipe.slug] = recipe.displayName
            var ingredientBlob: [String] = []
            ingredientBlob.reserveCapacity(recipe.ingredients.count)
            for line in recipe.ingredients {
                if ingredientNames[line.ingredientId] == nil {
                    ingredientNames[line.ingredientId] = line.displayName
                }
                ingredientBlob.append(line.displayName)
            }
            searchBlobs[recipe.slug] = [
                ingredientBlob.joined(separator: " "),
                recipe.category,
                recipe.sourceTitle,
                recipe.userNotes,
            ].joined(separator: " ")
        }
        let built = Base(
            key: key,
            candidates: unrated,
            displayNames: displayNames,
            ingredientNames: ingredientNames,
            searchBlobs: searchBlobs
        )
        base = built
        unratedIndex = makeIndex(from: built, candidates: unrated)
        overlaidKey = nil
        overlaidIndex = nil
    }

    private static func publish(ratings: [String: MealRating]) -> CatalogIndex {
        guard let base else {
            return CatalogIndex(key: 0, candidates: [], bySlug: [:], displayNames: [:], ingredientNames: [:])
        }
        if ratings.isEmpty, let unratedIndex {
            return unratedIndex
        }
        let key = ratingsKey(ratings)
        if key == overlaidKey, let overlaidIndex {
            return overlaidIndex
        }
        let candidates = base.candidates.map { candidate in
            var copy = candidate
            copy.rating = ratings[candidate.slug]
            return copy
        }
        let index = makeIndex(from: base, candidates: candidates)
        overlaidKey = key
        overlaidIndex = index
        return index
    }

    private static func makeIndex(from base: Base, candidates: [PickerCandidate]) -> CatalogIndex {
        CatalogIndex(
            key: base.key,
            candidates: candidates,
            bySlug: Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first }),
            displayNames: base.displayNames,
            ingredientNames: base.ingredientNames,
            searchBlobs: base.searchBlobs
        )
    }

    private static func ratingsKey(_ ratings: [String: MealRating]) -> Int {
        var hasher = Hasher()
        hasher.combine(ratings.count)
        for (slug, rating) in ratings.sorted(by: { $0.key < $1.key }) {
            hasher.combine(slug)
            hasher.combine(rating.rawValue)
        }
        return hasher.finalize()
    }

    private static func recipeKey(_ recipes: [Recipe]) -> Int {
        var hasher = Hasher()
        hasher.combine(recipes.count)
        for recipe in recipes {
            hasher.combine(recipe.persistentModelID)
            hasher.combine(recipe.slug)
            hasher.combine(recipe.nameTR)
            hasher.combine(recipe.nameEN)
            hasher.combine(recipe.nativeName)
            hasher.combine(recipe.totalMinutes)
            hasher.combine(recipe.trDogfoodScore)
            hasher.combine(recipe.country)
            hasher.combine(recipe.category)
            hasher.combine(recipe.unitoolsCategory)
            hasher.combine(recipe.difficulty)
            hasher.combine(recipe.tags)
            hasher.combine(recipe.diets)
            hasher.combine(recipe.originRaw)
            hasher.combine(recipe.collectionStateRaw)
            hasher.combine(recipe.sourceURL)
            hasher.combine(recipe.timeIsUnknown)
        }
        return hasher.finalize()
    }
}
