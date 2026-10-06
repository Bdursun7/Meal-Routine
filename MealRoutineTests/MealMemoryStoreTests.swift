import SwiftData
import XCTest
@testable import MealRoutine

@MainActor
final class MealMemoryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var previousAccount: HouseholdUser?
    private var previousSnapshot = HouseholdSnapshot.empty()

    override func setUp() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
        previousAccount = HouseholdSession.shared.account
        previousSnapshot = HouseholdSession.shared.snapshot
        HouseholdSession.shared.account = nil
        HouseholdSession.shared.snapshot = .empty()
    }

    override func tearDown() async throws {
        HouseholdSession.shared.account = previousAccount
        HouseholdSession.shared.snapshot = previousSnapshot
        UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
        container = nil
    }

    func testBehaviorEventsPersistCountsAndLastCookedDate() throws {
        let context = container.mainContext
        let cookedAt = TestFixtures.now
        var snapshot = try BehaviorTrackingService.record(.cooked, recipeSlug: "kofte", at: cookedAt, in: context)
        XCTAssertEqual(snapshot.timesCooked, 1)
        XCTAssertEqual(snapshot.lastCookedAt, cookedAt)
        XCTAssertEqual(snapshot.confidence, .low)

        snapshot = try BehaviorTrackingService.record(.replaced, recipeSlug: "kofte", in: context)
        XCTAssertEqual(snapshot.timesReplaced, 1)
        snapshot = try BehaviorTrackingService.record(.skipped, recipeSlug: "kofte", in: context)
        XCTAssertEqual(snapshot.timesSkipped, 1)
        snapshot = try BehaviorTrackingService.record(.loved, recipeSlug: "kofte", in: context)
        XCTAssertEqual(snapshot.lovedCount, 1)
        XCTAssertEqual(snapshot.latestRating, .loved)
        snapshot = try BehaviorTrackingService.record(.okay, recipeSlug: "kofte", in: context)
        XCTAssertEqual(snapshot.okayCount, 1)
        XCTAssertEqual(snapshot.latestRating, .okay)
        snapshot = try BehaviorTrackingService.record(.neverAgain, recipeSlug: "kofte", in: context)
        XCTAssertTrue(snapshot.neverAgain)
        XCTAssertEqual(snapshot.latestRating, .never)

        let stored = try MealMemoryService.snapshots(in: context)["kofte"]
        XCTAssertEqual(stored?.timesCooked, 1)
        XCTAssertEqual(stored?.timesReplaced, 1)
        XCTAssertEqual(stored?.timesSkipped, 1)
        XCTAssertEqual(stored?.lastCookedAt, cookedAt)
        XCTAssertEqual(stored?.latestRating, .never)
    }

    func testSkipRecordsMemoryAndLeavesTheGroceryRow() throws {
        let context = container.mainContext
        let now = TestFixtures.now
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), householdSize: 3)
        context.insert(week)
        let meal = PlannedMeal(dayOffset: 0, recipeSlug: "pilav", servings: 3)
        context.insert(meal)
        meal.week = week
        let groceryID = UUID()
        let item = GroceryItem(
            uuid: groceryID,
            ingredientId: "rice",
            nameTR: "Pirinç",
            nameEN: "Rice",
            quantity: 2,
            unit: "su bardağı",
            hasUnitConflict: false
        )
        context.insert(item)
        item.week = week
        try context.save()

        try WeekPlanService.markSkipped(uuid: meal.uuid, in: context, at: now)

        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let storedMeal = try XCTUnwrap(meals.first { $0.uuid == meal.uuid })
        XCTAssertEqual(storedMeal.recipeSlug, "pilav")
        XCTAssertEqual(storedMeal.skippedAt, now)
        XCTAssertNil(storedMeal.cookedAt)

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertEqual(groceries.map(\.uuid), [groceryID])
        XCTAssertEqual(groceries.first?.quantity, 2)
        XCTAssertEqual(try MealMemoryService.snapshots(in: context)["pilav"]?.timesSkipped, 1)

        try WeekPlanService.markSkipped(uuid: meal.uuid, in: context, at: now.addingTimeInterval(60))
        XCTAssertEqual(try MealMemoryService.snapshots(in: context)["pilav"]?.timesSkipped, 1)
        XCTAssertEqual(storedMeal.skippedAt, now)
    }

    func testSkipDoesNotOverrideACookedMeal() throws {
        let context = container.mainContext
        let meal = PlannedMeal(dayOffset: 1, recipeSlug: "corba", servings: 2, cookedAt: TestFixtures.now)
        context.insert(meal)
        try context.save()

        try WeekPlanService.markSkipped(uuid: meal.uuid, in: context, at: TestFixtures.now)

        XCTAssertNil(meal.skippedAt)
        XCTAssertNil(try MealMemoryService.snapshots(in: context)["corba"])
        XCTAssertFalse(SkipControl.showsAffordance(isCooked: true))
    }

    func testCookingClearsAnEarlierSkip() throws {
        let context = container.mainContext
        let meal = PlannedMeal(dayOffset: 2, recipeSlug: "pilav", servings: 2)
        context.insert(meal)
        try context.save()

        try WeekPlanService.markSkipped(uuid: meal.uuid, in: context, at: TestFixtures.now)
        XCTAssertNotNil(meal.skippedAt)
        XCTAssertTrue(SkipControl.recordsAsSkipped(skippedAt: meal.skippedAt, cookedAt: meal.cookedAt))

        let cookedAt = TestFixtures.now.addingTimeInterval(3_600)
        try WeekPlanService.markCooked(uuid: meal.uuid, in: context, at: cookedAt)

        XCTAssertEqual(meal.cookedAt, cookedAt)
        XCTAssertNil(meal.skippedAt)
        XCTAssertFalse(SkipControl.recordsAsSkipped(skippedAt: meal.skippedAt, cookedAt: meal.cookedAt))
        XCTAssertFalse(SkipControl.showsAffordance(isCooked: meal.cookedAt != nil))
    }

    func testResetClearsMemoryAndKeepsOnboardingPrefs() throws {
        let context = container.mainContext
        let prefs = UserPrefs(
            householdSize: 4,
            eveningsPerWeek: 5,
            maxCookMinutes: 45,
            dislikedIngredientIds: ["onion"],
            hasCompletedOnboarding: true,
            createdAt: TestFixtures.now
        )
        prefs.discoveryLevel = .adventurous
        prefs.repeatPreference = .occasionally
        prefs.difficultyPreference = .easyOnly
        prefs.weekdayStyle = .mostlyQuick
        prefs.dismissedPatternIDs = ["quick-meals"]
        prefs.didBackfillMealMemory = false
        context.insert(prefs)
        context.insert(MealMemory(snapshot: MealMemorySnapshot(recipeID: "pilav", timesCooked: 2, lovedCount: 1)))
        context.insert(MealBehaviorEvent(recipeSlug: "pilav", eventType: .cooked, createdAt: TestFixtures.now))
        context.insert(RecipeFeedback(recipeSlug: "pilav", rating: .loved, cooked: true, createdAt: TestFixtures.now))
        UserDefaults.standard.set(["pilav|1|1"], forKey: MealExposureLog.storageKey)
        try context.save()

        try MealMemoryService.reset(in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<MealMemory>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealBehaviorEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RecipeFeedback>()).isEmpty)
        XCTAssertNil(UserDefaults.standard.object(forKey: MealExposureLog.storageKey))

        let kept = try XCTUnwrap(UserPrefsStore.existing(in: context))
        XCTAssertEqual(kept.householdSize, 4)
        XCTAssertEqual(kept.eveningsPerWeek, 5)
        XCTAssertEqual(kept.maxCookMinutes, 45)
        XCTAssertEqual(kept.dislikedIngredientIds, ["onion"])
        XCTAssertTrue(kept.hasCompletedOnboarding)
        XCTAssertEqual(kept.discoveryLevel, .adventurous)
        XCTAssertEqual(kept.repeatPreference, .occasionally)
        XCTAssertEqual(kept.difficultyPreference, .easyOnly)
        XCTAssertEqual(kept.weekdayStyle, .mostlyQuick)
        XCTAssertTrue(kept.dismissedPatternIDs.isEmpty)
        XCTAssertTrue(kept.didBackfillMealMemory)
    }

    func testRegenerateKeepsCookedMealsAndReplacesSkippedOnes() throws {
        let context = container.mainContext
        let now = Date()
        insertPrefs(in: context, disliked: ["mushroom"])
        makeRecipe(slug: "pilav", name: "Pilav", ingredientId: "rice", ingredientName: "Pirinç", in: context)
        makeRecipe(slug: "mantarli", name: "Mantarlı", ingredientId: "mushroom", ingredientName: "Mantar", in: context)
        makeRecipe(slug: "corba", name: "Çorba", ingredientId: "lentil", ingredientName: "Mercimek", in: context)
        makeRecipe(slug: "kofte", name: "Köfte", ingredientId: "beef", ingredientName: "Kıyma", in: context)
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), householdSize: 2)
        context.insert(week)
        let cooked = PlannedMeal(dayOffset: 1, recipeSlug: "pilav", servings: 2, cookedAt: now)
        let skipped = PlannedMeal(dayOffset: 0, recipeSlug: "mantarli", servings: 2)
        context.insert(cooked)
        context.insert(skipped)
        cooked.week = week
        skipped.week = week
        skipped.skippedAt = now
        try context.save()
        let weekID = week.uuid
        let cookedID = cooked.uuid

        let replaced = try WeekPlanService.replaceCurrentWeek(
            in: context,
            request: PlanRequest(householdSize: 2, evenings: 3, maxCookMinutes: 60, dislikedIngredientIds: ["mushroom"]),
            now: now
        )
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)

        XCTAssertEqual(replaced.uuid, weekID)
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let kept = try XCTUnwrap(meals.first { $0.uuid == cookedID })
        XCTAssertEqual(kept.recipeSlug, "pilav")
        XCTAssertEqual(kept.cookedAt, now)
        XCTAssertEqual(kept.dayOffset, 1)
        XCTAssertFalse(meals.contains { $0.recipeSlug == "mantarli" })
        XCTAssertEqual(meals.filter { $0.cookedAt == nil }.count, 2)
        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertTrue(groceries.contains { $0.ingredientId == "rice" })
        XCTAssertFalse(groceries.contains { $0.ingredientId == "mushroom" })
    }

    func testPersonalPlanDoesNotOverwriteASharedWeek() throws {
        let context = container.mainContext
        insertPrefs(in: context, disliked: [])
        let now = Date()
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), householdSize: 2)
        context.insert(week)
        let meal = PlannedMeal(dayOffset: 0, recipeSlug: "pilav", servings: 2, cookedAt: now)
        context.insert(meal)
        meal.week = week
        try context.save()

        let user = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let snapshot = try HouseholdReducer.createHousehold(user: user, name: "Ev", now: now)
        HouseholdSession.shared.account = user
        HouseholdSession.shared.snapshot = snapshot

        XCTAssertThrowsError(
            try WeekPlanService.replaceCurrentWeek(
                in: context,
                request: PlanRequest(householdSize: 2, evenings: 3, maxCookMinutes: 60, dislikedIngredientIds: []),
                now: now
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, WeekPlanError.sharedWeek.errorDescription)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedMeal>()).map(\.recipeSlug), ["pilav"])
        XCTAssertNil(try WeekPlanService.ensureCurrentWeek(in: context, now: now.addingTimeInterval(14 * 86_400)))
    }

    func testReplacementRebuildsTheGroceryList() throws {
        let context = container.mainContext
        let now = Date()
        insertPrefs(in: context, disliked: [])
        makeRecipe(slug: "pilav", name: "Pilav", ingredientId: "rice", ingredientName: "Pirinç", in: context)
        makeRecipe(slug: "salata", name: "Salata", ingredientId: "tomato", ingredientName: "Domates", in: context)
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), householdSize: 2)
        context.insert(week)
        let meal = PlannedMeal(dayOffset: 0, recipeSlug: "pilav", servings: 2)
        context.insert(meal)
        meal.week = week
        try context.save()
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryItem>()).contains { $0.ingredientId == "rice" })

        try WeekPlanService.replaceMeal(uuid: meal.uuid, with: "salata", in: context)

        let groceries = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertTrue(groceries.contains { $0.ingredientId == "tomato" })
        XCTAssertFalse(groceries.contains { $0.ingredientId == "rice" })
        XCTAssertEqual(meal.recipeSlug, "salata")
    }

    func testVetoDropsTheGroceryRowAndSkipKeepsIt() throws {
        let context = container.mainContext
        let now = Date()
        insertPrefs(in: context, disliked: [])
        makeRecipe(slug: "pilav", name: "Pilav", ingredientId: "rice", ingredientName: "Pirinç", in: context)
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), householdSize: 2)
        context.insert(week)
        let mealID = UUID()
        let meal = PlannedMeal(uuid: mealID, dayOffset: 0, recipeSlug: "pilav", servings: 2)
        context.insert(meal)
        meal.week = week
        meal.skippedAt = now
        try context.save()

        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryItem>()).contains { $0.ingredientId == "rice" })

        let user = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        var snapshot = try HouseholdReducer.createHousehold(user: user, name: "Ev", now: now)
        try HouseholdReducer.installPlan(
            snapshot: &snapshot,
            drafts: [HouseholdMealDraft(dayOffset: 0, recipeSlug: "pilav", title: "Pilav", recipeOwnerUserId: nil)],
            weekStart: WeekCalendar.weekStart(containing: now),
            actor: user,
            now: now,
            mealIds: [mealID]
        )
        _ = try HouseholdReducer.setReaction(
            snapshot: &snapshot,
            mealId: mealID,
            user: user,
            reaction: .veto,
            now: now
        )
        HouseholdSession.shared.account = user
        HouseholdSession.shared.snapshot = snapshot
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)
        XCTAssertFalse(try context.fetch(FetchDescriptor<GroceryItem>()).contains { $0.ingredientId == "rice" })
    }

    private func insertPrefs(in context: ModelContext, disliked: [String]) {
        let prefs = UserPrefs(
            householdSize: 2,
            eveningsPerWeek: 3,
            maxCookMinutes: 60,
            dislikedIngredientIds: disliked,
            hasCompletedOnboarding: true,
            createdAt: TestFixtures.now
        )
        context.insert(prefs)
    }

    private func makeRecipe(
        slug: String,
        name: String,
        ingredientId: String,
        ingredientName: String,
        in context: ModelContext
    ) {
        let recipe = Recipe(
            slug: slug,
            nameEN: name,
            nameTR: name,
            nativeName: "",
            summaryEN: "",
            summaryTR: "",
            country: "TR",
            category: "main",
            unitoolsCategory: "main",
            diets: [],
            difficulty: "easy",
            baseServings: 2,
            prepMinutes: 10,
            cookMinutes: 20,
            totalMinutes: 30,
            tags: [],
            trDogfoodScore: 50,
            hardIngredientPenalty: 0,
            calories: 0,
            protein: 0,
            fat: 0,
            carbs: 0,
            sourceProvider: "",
            sourceLicense: "",
            sourceAttribution: "",
            photoURL: "",
            photoAuthor: "",
            photoLicense: ""
        )
        let line = IngredientLine(
            ingredientId: ingredientId,
            nameEN: ingredientName,
            nameTR: ingredientName,
            quantity: 1,
            unit: "g",
            scaling: "fixed",
            note: "",
            trAliasCurated: false,
            sortIndex: 0
        )
        let step = RecipeStep(textEN: "Pişir", textTR: "Pişir", minutes: nil, sortIndex: 0)
        line.recipe = recipe
        step.recipe = recipe
        recipe.ingredients = [line]
        recipe.steps = [step]
        context.insert(recipe)
        context.insert(line)
        context.insert(step)
    }
}
