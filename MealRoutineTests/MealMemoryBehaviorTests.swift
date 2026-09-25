import XCTest
@testable import MealRoutine

final class MealMemoryBehaviorTests: XCTestCase {
    func testCookReplaceAndSkipIncrement() {
        var memory = MealMemorySnapshot(recipeID: "kofte")
        let firstCook = TestFixtures.now
        MealMemoryReducer.apply(event: .cooked, at: firstCook, to: &memory)
        XCTAssertEqual(memory.timesCooked, 1)
        XCTAssertEqual(memory.lastCookedAt, firstCook)
        XCTAssertEqual(memory.confidence, .low, "one cook is not a settled preference")

        let laterCook = firstCook.addingTimeInterval(86_400)
        MealMemoryReducer.apply(event: .cooked, at: laterCook, to: &memory)
        XCTAssertEqual(memory.timesCooked, 2)
        XCTAssertEqual(memory.lastCookedAt, laterCook)
        XCTAssertEqual(memory.confidence, .medium)

        let earlier = firstCook.addingTimeInterval(-86_400)
        MealMemoryReducer.apply(event: .cooked, at: earlier, to: &memory)
        XCTAssertEqual(memory.lastCookedAt, laterCook, "an older cook does not move the last cooked date back")

        MealMemoryReducer.apply(event: .replaced, at: firstCook, to: &memory)
        XCTAssertEqual(memory.timesReplaced, 1)
        MealMemoryReducer.apply(event: .skipped, at: firstCook, to: &memory)
        XCTAssertEqual(memory.timesSkipped, 1)
    }

    func testLovedOkayAndNeverPersistAndLaterRatingWins() {
        var memory = MealMemorySnapshot(recipeID: "pilav")
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now, to: &memory)
        XCTAssertEqual(memory.lovedCount, 1)
        XCTAssertEqual(memory.latestRating, .loved)
        XCTAssertTrue(memory.isFavorite)
        XCTAssertEqual(memory.confidence, .high)

        MealMemoryReducer.apply(event: .okay, at: TestFixtures.now.addingTimeInterval(10), to: &memory)
        XCTAssertEqual(memory.okayCount, 1)
        XCTAssertEqual(memory.lovedCount, 1)
        XCTAssertEqual(memory.latestRating, .okay)

        MealMemoryReducer.apply(event: .neverAgain, at: TestFixtures.now.addingTimeInterval(20), to: &memory)
        XCTAssertTrue(memory.neverAgain)
        XCTAssertFalse(memory.isFavorite)
        XCTAssertEqual(memory.latestRating, .never)
        XCTAssertEqual(memory.confidence, .high)
    }

    func testSingleWeakEventStaysLowConfidence() {
        var replaced = MealMemorySnapshot(recipeID: "corba")
        MealMemoryReducer.apply(event: .replaced, at: TestFixtures.now, to: &replaced)
        XCTAssertEqual(replaced.timesReplaced, 1)
        XCTAssertEqual(replaced.confidence, .low)
        XCTAssertLessThan(ConfidenceCalculator.scale(6, confidence: .low), 6)

        var cooked = MealMemorySnapshot(recipeID: "corba")
        MealMemoryReducer.apply(event: .cooked, at: TestFixtures.now, to: &cooked)
        XCTAssertEqual(cooked.confidence, .low)

        let profile = PersonalizedScoringService.profile(
            memories: ["corba": cooked],
            candidates: [TestFixtures.candidate("corba", category: "soup", protein: "legume")]
        )
        XCTAssertTrue(profile.lovedCategories.isEmpty)
        XCTAssertTrue(profile.lovedProteins.isEmpty)
        XCTAssertEqual(MealMemoryReducer.dataPointCount(in: [replaced]), 1)
    }

    func testLaterOkayClearsTheLovedBoost() {
        var memory = MealMemorySnapshot(recipeID: "pilav")
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now.addingTimeInterval(-20 * 86_400), to: &memory)
        let loved = score("pilav", memory: memory)
        XCTAssertEqual(loved.behavior, 10)

        MealMemoryReducer.apply(event: .okay, at: TestFixtures.now, to: &memory)
        let okay = score("pilav", memory: memory)
        XCTAssertEqual(okay.behavior, 2)
    }

    private func score(_ slug: String, memory: MealMemorySnapshot) -> RecipeMemoryScore {
        let recipe = TestFixtures.candidate(slug, score: 50)
        return PersonalizedScoringService.score(
            recipe,
            memories: [slug: memory],
            candidates: [recipe],
            preferences: TestFixtures.prefs(),
            anchors: [],
            dayOffset: 6,
            now: TestFixtures.now
        )
    }
}
