import XCTest

final class HouseholdFlowUITests: XCTestCase {
    func testTestModeWalksCreateJoinVetoAndReplacement() {
        let app = XCUIApplication()
        app.launchArguments = [HouseholdTestLaunchArgument, HouseholdTestResetArgument]
        app.launch()

        let start = app.buttons["Kuruluma başla"]
        if start.waitForExistence(timeout: 45) {
            start.tap()
            tap("Devam", in: app)
            tap("Devam", in: app)
            tap("Devam", in: app)
            tap("Atla", in: app)
            tap("Haftamı oluştur", in: app)
        }

        XCTAssertTrue(app.tabBars.buttons["Profil"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Profil"].tap()
        let open = app.buttons["household.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()

        let toggle = app.switches["household.testMode.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(String(describing: toggle.value ?? ""), "1")
        let badge = app.staticTexts["household.testBadge"].firstMatch
        let badgeOther = app.otherElements["household.testBadge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 3) || badgeOther.waitForExistence(timeout: 3))

        let signIn = app.buttons["household.testSignIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let name = app.textFields["Ev halkının adı"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test Evi")
        reveal(app.buttons["household.create"], in: app).tap()
        reveal(app.buttons["household.invite"], in: app).tap()

        let partnerJoin = reveal(app.buttons["household.partnerJoin"], in: app)
        partnerJoin.tap()
        // Join is async. Generating first races the partner's push and can leave the house without a partner.
        XCTAssertTrue(waitForDisappearance(partnerJoin, timeout: 15), "Test Partner did not join")
        reveal(app.buttons["household.generateWeek"], in: app).tap()
        dismissTestBanner(in: app)

        // Bu Hafta builds every card eagerly. The Household form is lazy, so its rows can be missing until scrolled.
        app.tabBars.buttons["Bu Hafta"].tap()
        XCTAssertTrue(app.navigationBars["Bu Hafta"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons.matching(identifier: "household.partner.veto").firstMatch.waitForExistence(timeout: 20),
            "Shared week has no Test Partner controls on Bu Hafta"
        )

        tapControl("household.partner.veto", in: app)
        XCTAssertTrue(element(labelContaining: "Karar gerekiyor", in: app).waitForExistence(timeout: 8))

        dismissTestBanner(in: app)
        tapControl("household.partner.replace", in: app)
        let notice = NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "yerine", "önerdi")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(notice).firstMatch.waitForExistence(timeout: 8),
            "Replacement notice did not appear"
        )
    }

    func testTestModeHappyPathShowsWeekMarketAndStaysHermetic() {
        let app = XCUIApplication()
        app.launchArguments = [HouseholdTestLaunchArgument, HouseholdTestResetArgument]
        app.launch()

        let start = app.buttons["Kuruluma başla"]
        if start.waitForExistence(timeout: 45) {
            start.tap()
            tap("Devam", in: app)
            tap("Devam", in: app)
            tap("Devam", in: app)
            tap("Atla", in: app)
            tap("Haftamı oluştur", in: app)
        }

        XCTAssertTrue(app.tabBars.buttons["Bu Hafta"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars["Bu Hafta"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Tarifler"].tap()
        XCTAssertTrue(app.navigationBars["Tarifler"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Market"].tap()
        let marketBar = app.navigationBars["Market"]
        let marketEmpty = app.staticTexts["Market henüz dolmadı"]
        XCTAssertTrue(marketBar.waitForExistence(timeout: 10) || marketEmpty.waitForExistence(timeout: 5))

        app.tabBars.buttons["Profil"].tap()
        let open = app.buttons["household.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let toggle = app.switches["household.testMode.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(String(describing: toggle.value ?? ""), "1")
    }

    private func dismissTestBanner(in app: XCUIApplication) {
        let button = app.buttons["household.testBanner.dismiss"]
        guard button.waitForExistence(timeout: 3), button.isHittable else { return }
        button.tap()
    }

    /// Taps the first hittable match, scrolling down and then back up. Existence alone is not asserted
    /// up front: a lazy list only exposes rows near the viewport.
    private func tapControl(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let query = app.buttons.matching(identifier: identifier)
        _ = query.firstMatch.waitForExistence(timeout: 10)
        for attempt in 0..<14 {
            for index in 0..<query.count {
                let element = query.element(boundBy: index)
                if element.exists, element.isHittable {
                    element.tap()
                    return
                }
            }
            if attempt < 7 {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTFail("\(identifier) never became tappable", file: file, line: line)
    }

    private func element(labelContaining text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return element
        }
        for _ in 0..<5 {
            app.swipeUp()
            if element.exists, element.isHittable {
                return element
            }
        }
        if let above = revealUp(element, in: app) {
            return above
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element
    }

    /// Brings a row back after a lazy list dropped it above the fold.
    private func revealUp(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        for _ in 0..<8 {
            app.swipeDown()
            if element.exists, element.isHittable {
                return element
            }
        }
        return nil
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
    }
}

/// Mirrors `HouseholdTestLaunch` without linking the app target.
private let HouseholdTestLaunchArgument = "-HouseholdTestMode"
private let HouseholdTestResetArgument = "-HouseholdTestReset"
