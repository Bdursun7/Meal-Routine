import XCTest
@testable import MealRoutine

final class SmartReplacementTests: XCTestCase {
    func testFasterSimilarFavoriteAndNewIntents() {
        let current = TestFixtures.candidate("aksam", minutes: 50, category: "soup", protein: "legume")
        let faster = TestFixtures.candidate("hizli", minutes: 20, category: "egg", protein: "egg")
        let slower = TestFixtures.candidate("yavas", minutes: 70, category: "stew", protein: "tofu")
        let loved = TestFixtures.candidate("tavuk", minutes: 40, category: "grill", protein: "poultry", rating: .loved)
        let similar = TestFixtures.candidate("sote", minutes: 35, category: "skillet", protein: "poultry")
        let favorite = TestFixtures.candidate("eski", minutes: 30, category: "seafood", protein: "seafood", rating: .loved)
        let fresh = TestFixtures.candidate("yeni", minutes: 30, cuisine: "GR", category: "salad", protein: "dairy")
        let rated = TestFixtures.candidate("bilinen", minutes: 25, category: "omelette", protein: "egg", rating: .okay)
        let catalog = [current, faster, slower, loved, similar, favorite, fresh, rated]
        let context = TestFixtures.replacementMemory()

        let fasterSlugs = slugs(catalog, current: current, chips: [.faster], memory: context)
        XCTAssertTrue(fasterSlugs.contains("hizli"))
        XCTAssertFalse(fasterSlugs.contains("yavas"))
        XCTAssertFalse(fasterSlugs.contains(current.slug))

        let similarSlugs = slugs(catalog, current: current, chips: [.similarLoved], memory: context)
        XCTAssertEqual(similarSlugs, ["sote"])

        let favoriteSlugs = slugs(catalog, current: current, chips: [.loved], memory: context)
        XCTAssertEqual(Set(favoriteSlugs), ["tavuk", "eski"])

        let newSlugs = slugs(catalog, current: current, chips: [.tryNew], memory: context)
        XCTAssertTrue(newSlugs.contains("yeni"))
        XCTAssertTrue(newSlugs.contains("hizli"))
        XCTAssertFalse(newSlugs.contains("bilinen"))
        XCTAssertFalse(newSlugs.contains("eski"))
    }

    func testNeverAgainStaysOutOfReplacement() {
        let current = TestFixtures.candidate("aksam", minutes: 50, protein: "legume")
        let banned = TestFixtures.candidate("asla", score: 99, minutes: 15, protein: "tofu", rating: .never)
        let hidden = TestFixtures.candidate("gizli", minutes: 15, protein: "egg")
        var memory = MealMemorySnapshot(recipeID: "gizli")
        memory.neverAgain = true
        let catalog = [current, banned, hidden, TestFixtures.candidate("guvenli", minutes: 20, protein: "dairy")]
        let slugs = slugs(
            catalog,
            current: current,
            chips: [.faster],
            memory: TestFixtures.replacementMemory(["gizli": memory])
        )
        XCTAssertFalse(slugs.contains("asla"))
        XCTAssertFalse(slugs.contains("gizli"))
        XCTAssertTrue(slugs.contains("guvenli"))
    }

    private func slugs(
        _ catalog: [PickerCandidate],
        current: PickerCandidate,
        chips: Set<ReplacementChip>,
        memory: ReplacementMemory
    ) -> [String] {
        MealReplacement.choices(
            catalog: catalog,
            current: current,
            blockedSlugs: [current.slug],
            maxCookMinutes: 60,
            dislikedIngredientIds: [],
            activeChips: chips,
            memory: memory
        ).map(\.slug)
    }
}
