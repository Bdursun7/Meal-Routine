import SwiftData
import XCTest
@testable import MealRoutine

final class HouseholdPlanningTests: XCTestCase {
    func testHouseholdCreateInviteReactionsConflictsAndScoring() {
        let failures = HouseholdLogicChecks.runAll()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}

@MainActor
final class HouseholdGroceryPreserveTests: XCTestCase {
    func testWeekRebuildKeepsManualPantryAndCookRows() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let now = Date()
        let start = WeekCalendar.weekStart(containing: now)
        context.insert(UserPrefs(householdSize: 2, hasCompletedOnboarding: true))
        let week = PlanWeek(weekStart: start, householdSize: 2)
        context.insert(week)
        let manualID = UUID()
        let manual = GroceryItem(
            uuid: manualID,
            ingredientId: "manual:\(manualID.uuidString)",
            nameTR: "Ekmek",
            nameEN: "Bread",
            quantity: 1,
            unit: "piece",
            hasUnitConflict: false,
            isChecked: true,
            isManual: true,
            sourceRaw: GroceryLineSource.typed.rawValue
        )
        context.insert(manual)
        manual.week = week
        let short = GroceryItem(
            ingredientId: "pantry-auto:tomato|unit:piece",
            nameTR: "Domates",
            nameEN: "Tomato",
            quantity: 0.6,
            unit: "kg",
            hasUnitConflict: false,
            isChecked: true,
            isManual: true,
            sourceRaw: GroceryLineSource.shortfall.rawValue
        )
        context.insert(short)
        short.week = week
        let cook = GroceryItem(
            ingredientId: "pantry-cook:meal:tomato|unit:piece",
            nameTR: "Domates",
            nameEN: "Tomato",
            quantity: 1,
            unit: "piece",
            hasUnitConflict: false,
            isChecked: false,
            isManual: false,
            sourceRaw: GroceryLineSource.cookGap.rawValue
        )
        context.insert(cook)
        cook.week = week
        let planRow = GroceryItem(
            ingredientId: "tomato",
            nameTR: "Domates",
            nameEN: "Tomato",
            quantity: 4,
            unit: "piece",
            hasUnitConflict: false,
            isChecked: false,
            isManual: false
        )
        context.insert(planRow)
        planRow.week = week
        let mealID = UUID()
        let meal = PlannedMeal(uuid: mealID, dayOffset: 0, recipeSlug: "missing-slug", servings: 2)
        meal.titleSnapshot = "Yok"
        context.insert(meal)
        meal.week = week
        try context.save()

        var snapshot = HouseholdSnapshot.empty(now: now)
        let planID = UUID()
        snapshot.plan = SharedMealPlan(
            id: planID,
            householdId: UUID(),
            weekStart: start,
            status: .draft,
            isFinalized: false,
            meals: [
                SharedMeal(
                    id: mealID,
                    planId: planID,
                    dayOffset: 0,
                    recipeSlug: "missing-slug",
                    title: "Yok",
                    recipeOwnerUserId: nil,
                    status: .proposed,
                    reactions: [],
                    revision: 1,
                    baseRevision: 1,
                    updatedAt: now,
                    cookedAt: nil,
                    replacedAt: nil
                ),
            ],
            revision: 1,
            baseRevision: 1,
            updatedAt: now
        )
        try? HouseholdPlanBridge.apply(snapshot: snapshot, in: context, now: now)
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        let manualRow = items.first { $0.uuid == manualID }
        XCTAssertEqual(manualRow?.isChecked, true)
        XCTAssertEqual(manualRow?.ingredientId, "manual:\(manualID.uuidString)")
        let shortfall = items.first { $0.ingredientId == "pantry-auto:tomato|unit:piece" }
        XCTAssertEqual(shortfall?.isChecked, true)
        XCTAssertEqual(shortfall?.quantity, 0.6)
        XCTAssertTrue(items.contains { $0.ingredientId.hasPrefix("pantry-cook:") })
    }
}
