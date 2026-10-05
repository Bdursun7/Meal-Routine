import XCTest

final class HouseholdFlowUITests: XCTestCase {
    func testTestModeWalksCreateJoinVetoAndReplacement() {
        let app = XCUIApplication()
        app.launchArguments = [HouseholdTestLaunchArgument]
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

        let join = app.buttons["household.partnerJoin"]
        XCTAssertTrue(join.waitForExistence(timeout: 5))
        join.tap()
        reveal(app.buttons["household.generateWeek"], in: app).tap()

        let veto = app.buttons["household.partner.veto"].firstMatch
        XCTAssertTrue(veto.waitForExistence(timeout: 20))
        veto.tap()
        XCTAssertTrue(app.staticTexts["Karar gerekiyor"].firstMatch.waitForExistence(timeout: 5))

        if app.buttons["Kapat"].waitForExistence(timeout: 2) {
            app.buttons["Kapat"].tap()
        }
        let replace = app.buttons["household.partner.replace"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        replace.tap()
        let banner = app.otherElements["household.testBanner"].firstMatch
        let notice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "yerine")).firstMatch
        let otherNotice = app.otherElements.containing(NSPredicate(format: "label CONTAINS %@", "yerine")).firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 8)
                || notice.waitForExistence(timeout: 2)
                || otherNotice.waitForExistence(timeout: 2)
        )
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return element
        }
        app.swipeUp()
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
    }
}

/// Mirrors `HouseholdTestLaunch.argument` without linking the app target.
private let HouseholdTestLaunchArgument = "-HouseholdTestMode"
