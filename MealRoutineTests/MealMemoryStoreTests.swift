import SwiftData
import XCTest
@testable import MealRoutine

@MainActor
final class MealMemoryStoreTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
    }

    override func tearDown() async throws {
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
}
