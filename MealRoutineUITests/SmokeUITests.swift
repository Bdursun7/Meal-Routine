import XCTest

/// Smoke flows against the `-uitest` fixture. No `sleep`. Every wait is `waitForExistence`
/// or an `XCTNSPredicateExpectation`.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
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

        let partial = app.switches["cook.include.1"]
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        if (partial.value as? String) == "1" {
            partial.tap()
        }
        let leftOut = NSPredicate(format: "label CONTAINS %@", "Bu onayda düşülmez")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: leftOut, object: partial)], timeout: 5),
            .completed
        )

        app.buttons["cook.deduct"].tap()
        let sheet = app.navigationBars["Evdekilerden düş"]
        let closed = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: closed, object: sheet)], timeout: 8),
            .completed
        )

        openPantry(app)
        let fridgeRow = app.descendants(matching: .any)["pantry.row.tomato.refrigerator"]
        let pantryRow = app.descendants(matching: .any)["pantry.row.tomato.pantry"]
        let onionRow = app.descendants(matching: .any)["pantry.row.onion.pantry"]
        XCTAssertTrue(fridgeRow.waitForExistence(timeout: 8))
        XCTAssertTrue(pantryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(onionRow.waitForExistence(timeout: 5))
        XCTAssertTrue(fridgeRow.label.contains("1 adet"))
        XCTAssertFalse(fridgeRow.label.contains("2 adet"))
        XCTAssertTrue(pantryRow.label.contains("1 adet"))
        XCTAssertTrue(onionRow.label.contains("1 adet"))
    }

    func testPantryTabsAddTheSameIngredientInTwoPlaces() {
        let app = launch()
        openPantry(app)

        app.buttons["pantry.location.pantry"].tap()
        let kilerTomato = app.descendants(matching: .any)["pantry.row.tomato.pantry"]
        XCTAssertTrue(kilerTomato.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.tomato.refrigerator"].exists)

        addMiso(quantity: "2", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["pantry.row.miso.pantry"].waitForExistence(timeout: 8))

        app.buttons["pantry.location.refrigerator"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pantry.row.tomato.refrigerator"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.miso.pantry"].exists)

        addMiso(quantity: "1", in: app)
        let fridgeMiso = app.descendants(matching: .any)["pantry.row.miso.refrigerator"]
        XCTAssertTrue(fridgeMiso.waitForExistence(timeout: 8))
        XCTAssertTrue(fridgeMiso.label.contains("1 adet"))
        XCTAssertFalse(app.descendants(matching: .any)["pantry.row.miso.pantry"].exists)

        app.buttons["pantry.location.all"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pantry.row.miso.pantry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["pantry.row.miso.refrigerator"].exists)
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
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
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
