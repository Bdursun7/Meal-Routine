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

        reveal(app.buttons["household.partnerJoin"], in: app).tap()
        reveal(app.buttons["household.generateWeek"], in: app).tap()
        dismissTestBanner(in: app)

        tapControl("household.partner.veto", in: app)
        XCTAssertTrue(app.staticTexts["Karar gerekiyor"].firstMatch.waitForExistence(timeout: 5))

        dismissTestBanner(in: app)
        tapControl("household.partner.replace", in: app)
        let notice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "yerine")).firstMatch
        let otherNotice = app.otherElements.containing(NSPredicate(format: "label CONTAINS[c] %@", "yerine")).firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 8) || otherNotice.waitForExistence(timeout: 2)
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

    /// Picks a visible control. The same identifier also exists on Bu Hafta cards, which may be off this screen.
    private func tapControl(_ identifier: String, in app: XCUIApplication) {
        let query = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<5 {
            for index in 0..<query.count {
                let element = query.element(boundBy: index)
                if element.exists, element.isHittable {
                    element.tap()
                    return
                }
            }
            app.swipeUp()
        }
        XCTFail("\(identifier) never became tappable")
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
