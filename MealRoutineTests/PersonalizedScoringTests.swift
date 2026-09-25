import XCTest
@testable import MealRoutine

final class PersonalizedScoringTests: XCTestCase {
    func testLovedBoostAndSoftReplacePenalty() {
        var loved = MealMemorySnapshot(recipeID: "pilav")
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now.addingTimeInterval(-20 * 86_400), to: &loved)
        let lovedScore = PersonalizedScoringService.score(
            TestFixtures.candidate("pilav", score: 50),
            memories: ["pilav": loved],
            candidates: [TestFixtures.candidate("pilav", score: 50)],
            preferences: TestFixtures.prefs(),
            anchors: [],
            dayOffset: 0,
            now: TestFixtures.now
        )
        XCTAssertEqual(lovedScore.behavior, 10)

        var once = MealMemorySnapshot(recipeID: "tek")
        MealMemoryReducer.apply(event: .replaced, at: TestFixtures.now.addingTimeInterval(-30 * 86_400), to: &once)
        let soft = PersonalizedScoringService.score(
            TestFixtures.candidate("tek", score: 80),
            memories: ["tek": once],
            candidates: [TestFixtures.candidate("tek", score: 80)],
            preferences: TestFixtures.prefs(),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        )
        XCTAssertLessThan(soft.behavior, 0)
        XCTAssertGreaterThan(soft.behavior, -6)

        var repeated = MealMemorySnapshot(recipeID: "uzun")
        for _ in 0..<3 {
            MealMemoryReducer.apply(event: .replaced, at: TestFixtures.now.addingTimeInterval(-30 * 86_400), to: &repeated)
        }
        let full = PersonalizedScoringService.score(
            TestFixtures.candidate("uzun", score: 80),
            memories: ["uzun": repeated],
            candidates: [TestFixtures.candidate("uzun", score: 80)],
            preferences: TestFixtures.prefs(),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        )
        XCTAssertLessThanOrEqual(full.behavior, -6)
    }

    func testNeverAgainIsExcludedAndASlugIsNotRepeated() {
        let never = TestFixtures.candidate("asla", score: 99, rating: .never)
        let safe = TestFixtures.candidate("guvenli", score: 40)
        let week = PersonalizedScoringService.select(
            candidates: [never, safe, safe],
            evenings: 2,
            preferences: TestFixtures.prefs(),
            memories: ["asla": MealMemorySnapshot(recipeID: "asla", neverAgain: true)],
            now: TestFixtures.now
        )
        XCTAssertFalse(week.slugs.contains("asla"))
        XCTAssertEqual(Set(week.slugs).count, week.slugs.count)
    }

    func testDiscoveryAndRepetitionPreferencesChangeTheScore() {
        let chicken = TestFixtures.candidate("tavuk", score: 70, category: "main", protein: "poultry")
        let other = TestFixtures.candidate("sote", score: 55, category: "main", protein: "poultry")
        var loveA = MealMemorySnapshot(recipeID: "tavuk")
        var loveB = MealMemorySnapshot(recipeID: "izgara")
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now.addingTimeInterval(-20 * 86_400), to: &loveA)
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now.addingTimeInterval(-20 * 86_400), to: &loveB)
        let izgara = TestFixtures.candidate("izgara", score: 70, category: "main", protein: "poultry")
        let catalog = [chicken, izgara, other]
        let memories = ["tavuk": loveA, "izgara": loveB]

        let familiar = PersonalizedScoringService.score(
            other,
            memories: memories,
            candidates: catalog,
            preferences: TestFixtures.prefs(discovery: .familiar),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        )
        let adventurous = PersonalizedScoringService.score(
            other,
            memories: memories,
            candidates: catalog,
            preferences: TestFixtures.prefs(discovery: .adventurous),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        )
        XCTAssertGreaterThan(adventurous.discovery, familiar.discovery)

        var recent = loveA
        recent.lastCookedAt = TestFixtures.now.addingTimeInterval(-4 * 86_400)
        let balanced = penalty(recent, .balanced)
        let rare = penalty(recent, .occasionally)
        let often = penalty(recent, .often)
        XCTAssertEqual(balanced, 5)
        XCTAssertGreaterThan(rare, balanced)
        XCTAssertLessThan(often, balanced)
    }

    func testPlanExplanationIsDeterministicAndCountsRealPicks() {
        let picks = [
            PlannedPick(slug: "a", minutes: 20, dayOffset: 0, isNew: true, wasLoved: false),
            PlannedPick(slug: "b", minutes: 25, dayOffset: 1, isNew: true, wasLoved: false),
            PlannedPick(slug: "c", minutes: 50, dayOffset: 5, isNew: false, wasLoved: false),
        ]
        let first = PlanExplanationBuilder.explain(picks: picks, hasBehavior: true)
        let second = PlanExplanationBuilder.explain(picks: picks, hasBehavior: true)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("2 yeni tarif"))
        XCTAssertFalse(first.lowercased().contains("her zaman"))

        let empty = PlanExplanationBuilder.explain(picks: [], hasBehavior: false)
        XCTAssertEqual(empty, PlanExplanationBuilder.noMemory)
        XCTAssertFalse(empty.contains("sevdiğin"))

        let loved = PlanExplanationBuilder.explain(
            picks: [
                PlannedPick(slug: "a", minutes: 40, dayOffset: 0, isNew: false, wasLoved: true),
                PlannedPick(slug: "b", minutes: 35, dayOffset: 1, isNew: false, wasLoved: true),
            ],
            hasBehavior: true
        )
        XCTAssertEqual(loved, PlanExplanationBuilder.lovedLean)
    }

    private func penalty(_ memory: MealMemorySnapshot, _ repetition: RepeatPreference) -> Int {
        PersonalizedScoringService.score(
            TestFixtures.candidate("tavuk", score: 50, protein: "poultry"),
            memories: ["tavuk": memory],
            candidates: [TestFixtures.candidate("tavuk", score: 50, protein: "poultry")],
            preferences: TestFixtures.prefs(repetition: repetition),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        ).repetitionPenalty
    }
}
