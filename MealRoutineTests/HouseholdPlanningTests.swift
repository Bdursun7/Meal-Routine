import XCTest
@testable import MealRoutine

final class HouseholdPlanningTests: XCTestCase {
    func testHouseholdCreateInviteReactionsConflictsAndScoring() {
        let failures = HouseholdLogicChecks.runAll()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
