import XCTest
@testable import MealRoutine

final class PantryTests: XCTestCase {
    func testCompatibleMassLeavesTheMissingGrams() {
        let lines = [PantryMarketLine(ingredientId: "tomato", quantity: 1000, unit: "g", isChecked: false, preserve: false)]
        let stock = [PantryCoverageLine(ingredientId: "tomato", quantity: 400, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock)
        XCTAssertEqual(adjusted.first?.quantity, 600)
        XCTAssertEqual(adjusted.first?.applied, true)
        XCTAssertEqual(adjusted.first?.incompatible, false)
        let again = PantryMarketCoverage.adjust(lines, pantry: stock)
        XCTAssertEqual(again, adjusted)
    }

    func testKilogramsConvertIntoTheSameMassFamily() {
        let lines = [PantryMarketLine(ingredientId: "tomato", quantity: 1, unit: "kg", isChecked: false, preserve: false)]
        let stock = [PantryCoverageLine(ingredientId: "tomato", quantity: 400, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock)
        XCTAssertEqual(adjusted.first?.quantity, 0.6)
    }

    func testIncompatibleUnitsAreNotSubtracted() {
        let lines = [PantryMarketLine(ingredientId: "egg", quantity: 6, unit: "piece", isChecked: false, preserve: false)]
        let stock = [PantryCoverageLine(ingredientId: "egg", quantity: 500, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock)
        XCTAssertEqual(adjusted.first?.quantity, 6)
        XCTAssertEqual(adjusted.first?.incompatible, true)
        XCTAssertEqual(adjusted.first?.applied, false)
    }

    func testCheckedMarketRowsStayUntouched() {
        let lines = [PantryMarketLine(ingredientId: "tomato", quantity: 1, unit: "kg", isChecked: true, preserve: true)]
        let stock = [PantryCoverageLine(ingredientId: "tomato", quantity: 400, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock)
        XCTAssertEqual(adjusted.first?.quantity, 1)
        XCTAssertEqual(adjusted.first?.applied, false)
    }

    func testFinishedShortageUsesMinimumAndDoesNotInventOne() {
        XCTAssertEqual(PantryFinishedMath.shortage(quantity: 0, minimum: 2), 2)
        XCTAssertEqual(PantryFinishedMath.shortage(quantity: 1, minimum: 2), 1)
        XCTAssertNil(PantryFinishedMath.shortage(quantity: 0, minimum: nil))
    }

    func testUnknownUnitsNeedAnExplicitSeparateChoice() {
        XCTAssertEqual(
            PantryUnitPolicy.decision(existingUnit: nil, existingQuantity: 0, incomingUnit: "kova", incomingQuantity: 1, confirmSeparate: false),
            .invalid
        )
        XCTAssertEqual(
            PantryUnitPolicy.decision(existingUnit: "g", existingQuantity: 400, incomingUnit: "piece", incomingQuantity: 2, confirmSeparate: false),
            .choiceRequired(existingUnit: "g")
        )
        if case .merge(let quantity, let unit) = PantryUnitPolicy.decision(
            existingUnit: "g", existingQuantity: 400, incomingUnit: "kg", incomingQuantity: 1, confirmSeparate: false
        ) {
            XCTAssertEqual(quantity, 1400)
            XCTAssertEqual(unit, "g")
        } else {
            XCTFail("gram and kilogram should merge")
        }
    }

    func testPersonalPantryIsNotOfferedUntilAHouseholdExists() {
        let household = UUID()
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: nil, resolvedHouseholdId: nil))
        XCTAssertTrue(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: household, resolvedHouseholdId: nil))
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: household, resolvedHouseholdId: household.uuidString))
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 0, householdId: household, resolvedHouseholdId: nil))
    }

    func testEmptyPantryDoesNotChangeThePlanSentence() {
        let candidate = TestFixtures.candidate("soup", ingredients: ["tomato"])
        XCTAssertEqual(PantryPlanningSignal.score(candidate: candidate, stock: []), 0)
        XCTAssertNil(PantryPlanningSignal.explanation(candidate: candidate, stock: []))
        let base = PlanExplanationBuilder.noMemory
        XCTAssertEqual(PantryPlanningSignal.annotated(base, candidates: [candidate], stock: []), base)
    }

    func testPantryExplanationUsesExactIngredientMatches() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tomato = TestFixtures.candidate("menemen", ingredients: ["tomato"])
        let stock = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", bestBefore: nil)]
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: tomato, stock: stock, now: now), PantryCopy.usesStock)
        let other = [PantryPlanningStock(ingredientId: "tomato-paste", quantity: 2, unit: "piece", bestBefore: now)]
        XCTAssertNil(PantryPlanningSignal.explanation(candidate: tomato, stock: other, now: now))
        let soon = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", bestBefore: now.addingTimeInterval(86_400))]
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: tomato, stock: soon, now: now), PantryCopy.approachingExpiry)
        let later = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", bestBefore: now.addingTimeInterval(10 * 86_400))]
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: tomato, stock: later, now: now), PantryCopy.usesStock)
    }

    func testNeverAgainAndBlockedSlugsStayOutWhenPantryMatches() {
        let never = TestFixtures.candidate("never", score: 99, ingredients: ["tomato"], rating: .never)
        let open = TestFixtures.candidate("open", score: 10, ingredients: [])
        let stock = [PantryPlanningStock(ingredientId: "tomato", quantity: 4, unit: "piece")]
        let picked = MealRecommender.pick(
            candidates: [never, open],
            evenings: 1,
            maxCookMinutes: 90,
            dislikedIngredientIds: [],
            pantryStock: stock
        )
        XCTAssertEqual(picked, ["open"])
        let disliked = MealRecommender.pick(
            candidates: [TestFixtures.candidate("blocked", score: 99, ingredients: ["tomato"]), open],
            evenings: 1,
            maxCookMinutes: 90,
            dislikedIngredientIds: ["tomato"],
            pantryStock: stock
        )
        XCTAssertEqual(disliked, ["open"])
        let vetoed = MealRecommender.pick(
            candidates: [TestFixtures.candidate("veto", score: 99, ingredients: ["tomato"]), open],
            evenings: 1,
            maxCookMinutes: 90,
            dislikedIngredientIds: [],
            excludingSlugs: ["veto"],
            pantryStock: stock
        )
        XCTAssertEqual(vetoed, ["open"])
    }

    func testCoverageKeyStaysStableSoARetryDoesNotMintANewMutation() {
        let lines = [PantryReconcileLine(ingredientId: "tomato", displayName: "Domates", quantity: 1000, unit: "g", checked: false)]
        XCTAssertEqual(PantryMarketCoverage.idempotencyKey(for: lines), PantryMarketCoverage.idempotencyKey(for: lines))
        XCTAssertEqual(PantryCopy.conflict, "Bu malzeme başka bir cihazda güncellendi.")
    }

    func testPantryConflictIsKeptAndAReconnectSendsThePendingOpOnce() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = SyncWorkItem(
            id: UUID(),
            entityType: "pantry",
            entityId: UUID().uuidString,
            operationType: "update",
            payload: Data(),
            createdAt: now,
            retryCount: 0,
            status: .pending
        )
        var sent = 0
        let offline = await SyncDrainer.drain(items: [item], online: false, now: now) { _ in
            sent += 1
            return .applied
        }
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(offline.first?.status, .pending)
        let conflict = await SyncDrainer.drain(items: offline, online: true, now: now) { _ in
            sent += 1
            return .conflict
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(conflict.first?.status, .requiresResolution)
        let replay = await SyncDrainer.drain(items: conflict, online: true, now: now.addingTimeInterval(30)) { _ in
            sent += 1
            return .applied
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(replay.first?.status, .requiresResolution)
    }
}
