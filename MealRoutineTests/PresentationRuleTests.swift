import XCTest
@testable import MealRoutine

final class PresentationRuleTests: XCTestCase {
    func testBadgesStayHiddenUntilHistoryExists() {
        var cooked = MealMemorySnapshot(recipeID: "pilav", timesCooked: 2)
        cooked.confidence = .medium
        XCTAssertNil(RecommendationReasonService.badge(for: cooked, hasHistory: false))
        XCTAssertNil(RecommendationReasonService.badge(for: nil, hasHistory: false))

        XCTAssertEqual(RecommendationReasonService.badge(for: cooked, hasHistory: true), .familiar)
        XCTAssertEqual(RecommendationReasonService.badge(for: nil, hasHistory: true), .new)
        XCTAssertEqual(FamiliarityBadge.familiar.title, "Tanıdık")
        XCTAssertEqual(FamiliarityBadge.new.title, "Yeni")
    }

    func testColdStartHidesPersonalizedRails() {
        let sections = DiscoverySections.make(
            candidates: [
                TestFixtures.candidate("asla", score: 99, protein: "tofu", rating: .never),
                TestFixtures.candidate("yumurta", minutes: 15, protein: "egg"),
            ],
            memories: [:],
            preferences: TestFixtures.prefs()
        )
        XCTAssertTrue(sections.isEmpty)

        var cooked = MealMemorySnapshot(recipeID: "yumurta", timesCooked: 1)
        cooked.confidence = .low
        let withHistory = DiscoverySections.make(
            candidates: [
                TestFixtures.candidate("asla", score: 99, protein: "tofu", rating: .never),
                TestFixtures.candidate("yumurta", minutes: 15, protein: "egg"),
            ],
            memories: ["yumurta": cooked],
            preferences: TestFixtures.prefs()
        )
        XCTAssertTrue(withHistory.contains { $0.id == "recommended" })
        XCTAssertEqual(withHistory.first { $0.id == "quick" }?.title, "Hızlı tarifler")
        XCTAssertFalse(withHistory.flatMap { $0.items.map(\.slug) }.contains("asla"))
        XCTAssertTrue(withHistory.allSatisfy { $0.items.allSatisfy { $0.badge != nil } })
    }

    func testSkipAppearanceIsSelectedOnlyAfterASkip() {
        XCTAssertEqual(
            SkipControl.appearance(isSkipped: false, isCooked: false, isWorking: false),
            .idle
        )
        XCTAssertFalse(SkipControl.usesFilledAccent(.idle))
        XCTAssertEqual(SkipControl.title(isSkipped: false), "Atladım")

        let selected = SkipControl.appearance(isSkipped: true, isCooked: false, isWorking: false)
        XCTAssertEqual(selected, .selected)
        XCTAssertTrue(SkipControl.usesFilledAccent(selected))
        XCTAssertEqual(SkipControl.title(isSkipped: true), "Atlandı")

        XCTAssertTrue(SkipControl.showsAffordance(isCooked: false))
        XCTAssertFalse(SkipControl.showsAffordance(isCooked: true))
        XCTAssertFalse(SkipControl.recordsAsSkipped(skippedAt: TestFixtures.now, cookedAt: TestFixtures.now))

        let cooked = meal(isCooked: true, isSkipped: true)
        XCTAssertFalse(cooked.showsSkip)
        XCTAssertFalse(cooked.showsSkippedChrome)

        let skipped = meal(isCooked: false, isSkipped: true)
        XCTAssertTrue(skipped.showsSkip)
        XCTAssertTrue(skipped.showsSkippedChrome)

        let idle = meal(isCooked: false, isSkipped: false)
        XCTAssertTrue(idle.showsSkip)
        XCTAssertFalse(idle.showsSkippedChrome)
        XCTAssertEqual(
            SkipControl.appearance(isSkipped: false, isCooked: false, isWorking: true),
            .unavailable
        )
    }

    func testCookBarRequiresTheOpenWeek() {
        let now = TestFixtures.now
        let thisWeek = WeekCalendar.weekStart(containing: now)
        let lastWeek = WeekCalendar.date(weekStart: thisWeek, dayOffset: -7)
        let mealID = UUID()

        XCTAssertTrue(
            CookBarGate.showsCookBar(
                allowsCookBar: true,
                plannedMealID: mealID,
                mealWeekStart: thisWeek,
                now: now
            )
        )
        XCTAssertFalse(
            CookBarGate.showsCookBar(
                allowsCookBar: false,
                plannedMealID: mealID,
                mealWeekStart: thisWeek,
                now: now
            )
        )
        XCTAssertFalse(
            CookBarGate.showsCookBar(
                allowsCookBar: true,
                plannedMealID: nil,
                mealWeekStart: thisWeek,
                now: now
            )
        )
        XCTAssertFalse(
            CookBarGate.showsCookBar(
                allowsCookBar: true,
                plannedMealID: mealID,
                mealWeekStart: lastWeek,
                now: now
            )
        )
    }

    private func meal(isCooked: Bool, isSkipped: Bool) -> WeekMealPresentation {
        WeekMealPresentation(
            id: UUID(),
            dayTitle: "Pazartesi",
            dateTitle: "Bugün",
            recipeName: "Pilav",
            minutes: 30,
            difficultyTitle: "Kolay",
            servings: 2,
            isCooked: isCooked,
            isToday: true,
            rating: nil,
            slug: "pilav",
            isSkipped: isSkipped
        )
    }
}
