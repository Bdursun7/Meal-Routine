import XCTest

/// Smoke flows against the `-uitest` fixture. No `sleep`. Every wait is `waitForExistence`
/// or an `XCTNSPredicateExpectation`.
final class SmokeUITests: XCTestCase {
    private var launched: XCUIApplication?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func record(_ issue: XCTIssue) {
        let app = launched ?? XCUIApplication()
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "UI hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Failure screenshot"
        shot.lifetime = .keepAlways
        add(shot)
        super.record(issue)
    }

    func testLaunchShowsTheFiveTabs() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Bu Hafta"].waitForExistence(timeout: 20))
        let tabs = [
            ("Tarifler", "Tarifler"),
            ("Market", "Market"),
            ("Hafıza", "Yemek hafızan"),
            ("Profil", "Profil"),
            ("Bu Hafta", "Bu Hafta"),
        ]
        for (tabTitle, screenTitle) in tabs {
            let tab = app.tabBars.buttons[tabTitle]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), tabTitle)
            tab.tap()
            XCTAssertTrue(app.navigationBars[screenTitle].waitForExistence(timeout: 10), screenTitle)
        }
    }

    func testRecipeHeroLeavesTheSpinner() {
        let app = launch()
        openRecipes(app)
        let row = app.descendants(matching: .any)["recipe.row.ui-aksam"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let hero = app.descendants(matching: .any)["recipe.photo.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        let shown = NSPredicate(format: "label == %@", "Tarif fotoğrafı")
        let expectation = XCTNSPredicateExpectation(predicate: shown, object: hero)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed)
        XCTAssertNotEqual(hero.label, "Fotoğraf yükleniyor")
    }

    func testCookSheetMovesTheSplitAndDeductsOnlyTheChosenPlace() {
        let app = launch()
        let open = app.descendants(matching: .any)["week.open.ui-aksam"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()

        let cook = app.buttons["cook.mark"]
        XCTAssertTrue(cook.waitForExistence(timeout: 10))
        cook.tap()

        let okay = app.buttons["cook.rating.okay"]
        XCTAssertTrue(okay.waitForExistence(timeout: 8))
        okay.tap()
        app.buttons["cook.rating.save"].tap()

        XCTAssertTrue(app.navigationBars["Evdekilerden düş"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Kiler: 1 adet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Buzdolabı: 0 adet"].exists)

        let plus = app.buttons["cook.split.plus.0.refrigerator"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(app.staticTexts["Buzdolabı: 1 adet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kiler: 0 adet"].waitForExistence(timeout: 5))

        // Index 1 is the seeded onion: need 2, Kiler stock 1, so it is the Yetersiz stok row.
        // A List Toggle's center hit is the label on iOS 26. The switch sits on the trailing edge.
        turnOffCookInclude(1, in: app)
        let leftOut = NSPredicate(
            format: "identifier == %@ AND value == %@",
            "cook.summary.1",
            "Bu onayda düşülmez"
        )
        let summary = app.descendants(matching: .any).matching(leftOut).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "cook.summary.1 value == Bu onayda düşülmez")

        app.buttons["cook.deduct"].tap()
        let sheet = app.navigationBars["Evdekilerden düş"]
        let closed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: closed, object: sheet)], timeout: 8),
            .completed
        )

        openPantry(app)
        let fridgeRow = reveal("pantry.row.tomato.refrigerator", in: app, within: "pantry.list")
        let pantryRow = reveal("pantry.row.tomato.pantry", in: app, within: "pantry.list")
        let onionRow = reveal("pantry.row.onion.pantry", in: app, within: "pantry.list")
        XCTAssertTrue(fridgeRow.waitForExistence(timeout: 8))
        XCTAssertTrue(pantryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(onionRow.waitForExistence(timeout: 5))
        XCTAssertEqual(fridgeRow.value as? String, "1 adet")
        XCTAssertTrue(fridgeRow.label.contains("1 adet"))
        XCTAssertFalse(fridgeRow.label.contains("2 adet"))
        XCTAssertEqual(pantryRow.value as? String, "1 adet")
        XCTAssertTrue(pantryRow.label.contains("1 adet"))
        XCTAssertEqual(onionRow.value as? String, "1 adet")
        XCTAssertTrue(onionRow.label.contains("1 adet"))
    }

    func testPantryTabsAddTheSameIngredientInTwoPlaces() {
        let app = launch()
        openPantry(app)

        selectPantryLocation("pantry", in: app)
        let kilerTomato = reveal("pantry.row.tomato.pantry", in: app, within: "pantry.list")
        XCTAssertTrue(kilerTomato.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.tomato.refrigerator"].exists)

        addMiso(quantity: "2", in: app)
        let kilerMiso = reveal("pantry.row.miso.pantry", in: app, within: "pantry.list")
        XCTAssertTrue(kilerMiso.waitForExistence(timeout: 8))
        XCTAssertEqual(kilerMiso.value as? String, "2 adet")

        selectPantryLocation("refrigerator", in: app)
        XCTAssertTrue(reveal("pantry.row.tomato.refrigerator", in: app, within: "pantry.list").waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.miso.pantry"].exists)

        addMiso(quantity: "1", in: app)
        let fridgeMiso = reveal("pantry.row.miso.refrigerator", in: app, within: "pantry.list")
        XCTAssertTrue(fridgeMiso.waitForExistence(timeout: 8))
        XCTAssertEqual(fridgeMiso.value as? String, "1 adet")
        XCTAssertTrue(fridgeMiso.label.contains("1 adet"))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.miso.pantry"].exists)

        selectPantryLocation("all", in: app)
        XCTAssertTrue(reveal("pantry.row.miso.pantry", in: app, within: "pantry.list").waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.descendants(matching: .any)["pantry.row.miso.pantry"].value as? String,
            "2 adet"
        )
        XCTAssertTrue(reveal("pantry.row.miso.refrigerator", in: app, within: "pantry.list").waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.descendants(matching: .any)["pantry.row.miso.refrigerator"].value as? String,
            "1 adet"
        )
    }

    func testMarketCanonicalCardShowsSourceLabels() {
        let app = launch()
        app.tabBars.buttons["Market"].tap()
        XCTAssertTrue(app.navigationBars["Market"].waitForExistence(timeout: 15))

        let tomatoCard = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "Plan:", "Evdekiler eksiği", "Pişirme eksiği", "Elle eklendi"
        )
        XCTAssertTrue(app.staticTexts.matching(tomatoCard).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["grocery.card.tomato.unit:piece"].exists)
        XCTAssertTrue(app.staticTexts["Eşik"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["grocery.card.milk.unit:piece"].exists)
    }

    func testLowStockThresholdShowsBadgeToggleAndMinimum() {
        let app = launch()
        openPantry(app)

        let toggle = app.switches["pantry.lowStock"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(toggle.label.contains("Düşük stok bildirimi"))

        let milk = app.descendants(matching: .any)["pantry.row.milk.pantry"]
        XCTAssertTrue(milk.waitForExistence(timeout: 8))
        XCTAssertTrue(milk.label.contains("Azaldı"))
        XCTAssertTrue(milk.label.contains("Minimum"))

        let edit = app.buttons["pantry.edit.milk.pantry"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let minimum = app.textFields["pantry.form.minimum"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 8))
        XCTAssertEqual(minimum.value as? String, "3")
        XCTAssertTrue(app.switches["Minimumun altına inince markete ekle"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        launched = app
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
    }

    /// Turns off `cook.include.<needIndex>`. The switch value stays "1"/"0"; the sentence is `cook.summary`.
    private func turnOffCookInclude(_ needIndex: Int, in app: XCUIApplication) {
        let identifier = "cook.include.\(needIndex)"
        let row = reveal(identifier, in: app, within: "cook.sheet", hittable: true)
        XCTAssertTrue(row.waitForExistence(timeout: 5), identifier)
        let named = app.switches[identifier]
        let host = named.exists ? named : row
        let nested = host.switches.firstMatch
        if nested.waitForExistence(timeout: 1) {
            nested.tap()
        } else {
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        if !waitUntilIncludedSwitchIsOff(identifier, in: app, timeout: 2) {
            if nested.exists {
                host.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            } else if host.switches.firstMatch.exists {
                host.switches.firstMatch.tap()
            }
            XCTAssertTrue(
                waitUntilIncludedSwitchIsOff(identifier, in: app, timeout: 4),
                "\(identifier) value == 0"
            )
        }
    }

    private func waitUntilIncludedSwitchIsOff(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let off = NSPredicate { _, _ in
            self.includedSwitchIsOff(identifier, in: app)
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: off, object: app)], timeout: timeout) == .completed
    }

    private func includedSwitchIsOff(_ identifier: String, in app: XCUIApplication) -> Bool {
        let candidates = [
            app.switches[identifier],
            app.switches[identifier].switches.firstMatch,
            app.descendants(matching: .any)[identifier],
            app.descendants(matching: .any)[identifier].switches.firstMatch,
        ]
        return candidates.contains { $0.exists && isSwitchOff($0) }
    }

    private func isSwitchOff(_ element: XCUIElement) -> Bool {
        let raw = element.value
        if let number = raw as? NSNumber { return number.intValue == 0 }
        if let text = raw as? String {
            return text == "0" || text.caseInsensitiveCompare("false") == .orderedSame
        }
        return false
    }

    private func selectPantryLocation(_ raw: String, in app: XCUIApplication) {
        let identifier = "pantry.location.\(raw)"
        let chip = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), identifier)
        let scroller = app.descendants(matching: .any)["pantry.location.scroller"]
        if !chip.isHittable && scroller.exists {
            for _ in 0..<3 where !chip.isHittable {
                scroller.swipeRight(velocity: .slow)
            }
            for _ in 0..<3 where !chip.isHittable {
                scroller.swipeLeft(velocity: .slow)
            }
        }
        chip.tap()
        let selected = NSPredicate(format: "identifier == %@ AND selected == true", identifier)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(selected).firstMatch.waitForExistence(timeout: 5),
            identifier
        )
    }

    /// SwiftUI lists omit off-screen cells. Swipe the named scroller until the identifier exists.
    @discardableResult
    private func reveal(
        _ identifier: String,
        in app: XCUIApplication,
        within scrollerID: String,
        hittable: Bool = false
    ) -> XCUIElement {
        let target = app.descendants(matching: .any)[identifier]
        let scroller = app.descendants(matching: .any)[scrollerID]
        let host = scroller.exists ? scroller : app
        func ready() -> Bool {
            guard target.exists else { return false }
            return hittable ? target.isHittable : true
        }
        if target.waitForExistence(timeout: 1), ready() { return target }
        for _ in 0..<5 where !ready() {
            host.swipeUp(velocity: .slow)
        }
        for _ in 0..<6 where !ready() {
            host.swipeDown(velocity: .slow)
        }
        return target
    }

    private func openRecipes(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Tarifler"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Tarifler"].tap()
        XCTAssertTrue(app.navigationBars["Tarifler"].waitForExistence(timeout: 10))
    }

    private func openPantry(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Profil"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let open = app.descendants(matching: .any)["pantry.open"]
        if !open.waitForExistence(timeout: 3) || !open.isHittable {
            for _ in 0..<4 {
                app.swipeUp()
                if open.exists, open.isHittable { break }
            }
        }
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        XCTAssertTrue(app.navigationBars["Evdekiler"].waitForExistence(timeout: 8))
    }

    private func addMiso(quantity: String, in app: XCUIApplication) {
        let add = app.buttons["pantry.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let name = app.textFields["pantry.form.ingredient"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Miso")
        let suggestion = app.buttons["pantry.suggestion.miso"]
        if suggestion.waitForExistence(timeout: 2), suggestion.isHittable {
            suggestion.tap()
        }
        let amount = app.textFields["pantry.form.quantity"]
        if !amount.waitForExistence(timeout: 2) || !amount.isHittable {
            app.sheets.firstMatch.swipeUp()
        }
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText(quantity)
        let save = app.buttons["pantry.form.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
    }
}
