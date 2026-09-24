import Foundation

/// Portion scaling and grocery reconcile checks. No SwiftData, no Xcode.
///
///   Tools/run_portion_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func close(_ lhs: Double?, _ rhs: Double, _ message: String) {
    guard let lhs else {
        check(false, "\(message) was nil")
        return
    }
    check(abs(lhs - rhs) < 0.000_1, "\(message) got \(lhs) expected \(rhs)")
}

private func scaled(
    _ quantity: Double?,
    scaling: String,
    base: Int,
    meal: Int?,
    household: Int
) -> Double? {
    PortionScaler.scale(
        quantity: quantity,
        scaling: scaling,
        baseServings: base,
        householdSize: ActiveServings.resolve(mealServings: meal, householdSize: household)
    )
}

private func checkActiveServings() {
    check(ActiveServings.resolve(mealServings: nil, householdSize: 2) == 2, "nil meal uses household")
    check(ActiveServings.resolve(mealServings: 0, householdSize: 3) == 3, "zero meal falls back")
    check(ActiveServings.resolve(mealServings: -2, householdSize: 5) == 5, "negative meal falls back")
    check(ActiveServings.resolve(mealServings: 4, householdSize: 2) == 4, "meal overrides household")
    check(ActiveServings.resolve(mealServings: 99, householdSize: 2) == 8, "meal clamps to 8")
    check(ActiveServings.resolve(mealServings: nil, householdSize: 0) == 1, "household clamps up to 1")
    check(ActiveServings.resolve(mealServings: nil, householdSize: 12) == 8, "household clamps down to 8")
    check(ActiveServings.resolve(mealServings: 1, householdSize: 8) == 1, "one person stays one")
}

private func checkScalingSemantics() {
    close(scaled(2, scaling: "linear", base: 4, meal: 8, household: 2), 4, "linear follows the meal, not the household")
    close(scaled(2, scaling: "linear", base: 4, meal: nil, household: 2), 1, "linear household default halves a base of 4")
    close(scaled(4, scaling: "damped", base: 4, meal: nil, household: 1), 2, "damped household 1 of base 4")
    close(scaled(4, scaling: "damped", base: 4, meal: 4, household: 1), 4, "damped meal at the base ignores household")
    close(scaled(4, scaling: "fixed", base: 4, meal: 8, household: 1), 4, "fixed ignores both counts")
    check(scaled(nil, scaling: "linear", base: 4, meal: 8, household: 2) == nil, "nil quantity stays nil")

    let householdTwo = scaled(200, scaling: "linear", base: 2, meal: nil, household: 4)
    close(householdTwo, 400, "household 2→4 doubles a base-2 linear row")
    let spice = scaled(2, scaling: "damped", base: 2, meal: nil, household: 4)
    close(spice, 2.0 * 2.0.squareRoot(), "household 2→4 damps spices")
    close(scaled(1, scaling: "fixed", base: 2, meal: nil, household: 4), 1, "household 2→4 leaves fixed rows")
}

private func checkPerMealGrocerySum() {
    let first = scaled(250, scaling: "linear", base: 4, meal: 2, household: 4)
    let second = scaled(1, scaling: "linear", base: 4, meal: 4, household: 4)
    let merged = GroceryMerger.merge([
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "Chicken", quantity: first, unit: "g"),
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "Chicken", quantity: second, unit: "kg"),
    ])
    check(merged.count == 1 && merged[0].unit == "kg", "per-meal chicken merges \(merged)")
    close(merged.first?.quantity, 1.125, "125 g at 2 servings + 1 kg at 4 servings")

    let oldHousehold = GroceryMerger.merge([
        GrocerySourceLine(
            ingredientId: "chicken",
            nameTR: "Tavuk",
            nameEN: "",
            quantity: scaled(250, scaling: "linear", base: 4, meal: nil, household: 2),
            unit: "g"
        ),
        GrocerySourceLine(
            ingredientId: "chicken",
            nameTR: "Tavuk",
            nameEN: "",
            quantity: scaled(1, scaling: "linear", base: 4, meal: nil, household: 2),
            unit: "kg"
        ),
    ])
    check(oldHousehold.count == 1 && oldHousehold[0].unit == "g", "household 2 chicken stays grams \(oldHousehold)")
    close(oldHousehold.first?.quantity, 625, "household 2 chicken grams")
}

private func checkReconcileKeepsChecks() {
    check(
        GroceryMerger.rowIdentity(ingredientId: "chicken", unit: "g")
            == GroceryMerger.rowIdentity(ingredientId: "chicken", unit: "kg"),
        "g and kg share a row identity"
    )
    check(
        GroceryMerger.rowIdentity(ingredientId: "chicken", unit: "GR")
            == GroceryMerger.rowIdentity(ingredientId: "chicken", unit: "kilogram"),
        "spelling aliases share a row identity"
    )
    check(
        GroceryMerger.rowIdentity(ingredientId: "onion", unit: "piece")
            != GroceryMerger.rowIdentity(ingredientId: "onion", unit: "g"),
        "piece and grams stay different rows"
    )

    let checked = UUID()
    let stored = GroceryMerger.merge([
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "", quantity: 625, unit: "g"),
    ])
    check(stored.first?.unit == "g", "stored household-2 row is grams")

    let grown = GroceryMerger.merge([
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "Chicken", quantity: 250, unit: "g"),
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "Chicken", quantity: 1, unit: "kg"),
    ])
    check(grown.first?.unit == "kg", "household-4 mix displays as kg \(grown)")
    close(grown.first?.quantity, 1.25, "250 g + 1 kg")

    let plan = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: checked, ingredientId: "chicken", unit: "g", quantity: 625, isChecked: true),
        ],
        merged: grown
    )
    check(plan.inserts.isEmpty && plan.deletes.isEmpty, "unit flip does not orphan the row \(plan)")
    check(
        plan.updates.count == 1 && plan.updates.first?.existingID == checked && plan.updates.first?.isChecked == false,
        "a larger amount clears the check when grams become kilograms \(plan)"
    )

    let sameMass = UUID()
    let equivalent = GroceryMerger.merge([
        GrocerySourceLine(ingredientId: "chicken", nameTR: "Tavuk", nameEN: "", quantity: 1, unit: "kg"),
    ])
    let sameAmount = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: sameMass, ingredientId: "chicken", unit: "g", quantity: 1_000, isChecked: true),
        ],
        merged: equivalent
    )
    check(sameAmount.inserts.isEmpty && sameAmount.deletes.isEmpty, "equivalent mass reuses the row \(sameAmount)")
    check(
        sameAmount.updates.count == 1
            && sameAmount.updates.first?.existingID == sameMass
            && sameAmount.updates.first?.isChecked == true,
        "check survives g → kg when the amount is the same"
    )

    let unchecked = UUID()
    let alsoChecked = UUID()
    let preferChecked = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: unchecked, ingredientId: "chicken", unit: "g", quantity: 625, isChecked: false),
            AutoGroceryRow(id: alsoChecked, ingredientId: "chicken", unit: "kg", quantity: 1.25, isChecked: true),
        ],
        merged: grown
    )
    check(
        preferChecked.updates.count == 1
            && preferChecked.updates.first?.existingID == alsoChecked
            && preferChecked.updates.first?.isChecked == true,
        "keep the checked duplicate"
    )
    check(preferChecked.deletes == [unchecked], "unchecked duplicate is removed \(preferChecked.deletes)")

    let piece = UUID()
    let grams = GroceryMerger.merge([
        GrocerySourceLine(ingredientId: "onion", nameTR: "Soğan", nameEN: "", quantity: 150, unit: "g"),
    ])
    let separate = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: piece, ingredientId: "onion", unit: "piece", quantity: 2, isChecked: true),
        ],
        merged: grams
    )
    check(separate.updates.isEmpty && separate.inserts == [0] && separate.deletes == [piece], "piece check is not applied to grams")
}

private func mergedLine(_ id: String, quantity: Double?, unit: String, name: String) -> [MergedGroceryLine] {
    GroceryMerger.merge([
        GrocerySourceLine(ingredientId: id, nameTR: name, nameEN: name, quantity: quantity, unit: unit),
    ])
}

private func checkQuantityChangeClearsCheck() {
    let tomato = UUID()
    let three = mergedLine("tomato", quantity: 3, unit: "piece", name: "Domates")
    let five = mergedLine("tomato", quantity: 5, unit: "piece", name: "Domates")
    check(three.first?.quantity == 3 && five.first?.quantity == 5, "tomato rows merge as pieces")

    let increased = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: tomato, ingredientId: "tomato", unit: "piece", quantity: 3, isChecked: true),
        ],
        merged: five
    )
    check(
        increased.updates.count == 1
            && increased.updates.first?.existingID == tomato
            && increased.inserts.isEmpty
            && increased.deletes.isEmpty
            && increased.updates.first?.isChecked == false,
        "checked tomato 3 → 5 is unchecked on the same row \(increased)"
    )

    let unchanged = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: tomato, ingredientId: "tomato", unit: "adet", quantity: 3, isChecked: true),
        ],
        merged: three
    )
    check(
        unchanged.updates.count == 1 && unchanged.updates.first?.isChecked == true,
        "unchanged tomato quantity stays checked"
    )

    let alreadyOpen = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: tomato, ingredientId: "tomato", unit: "piece", quantity: 3, isChecked: false),
        ],
        merged: five
    )
    check(alreadyOpen.updates.first?.isChecked == false, "an open row stays open when the amount grows")

    let customSame = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(
                id: tomato,
                ingredientId: "tomato",
                unit: "piece",
                quantity: 3,
                isChecked: true,
                quantityIsCustom: true
            ),
        ],
        merged: five
    )
    check(
        customSame.updates.first?.isChecked == true && customSame.deletes.isEmpty,
        "custom quantity 3 stays checked when the planned amount becomes 5"
    )

    check(
        GroceryCheckState.checkedAfterQuantityEdit(
            wasChecked: true,
            previousQuantity: 3,
            unit: "piece",
            editedQuantity: 5
        ) == false,
        "hand-edited 3 → 5 clears the check"
    )
    check(
        GroceryCheckState.checkedAfterQuantityEdit(
            wasChecked: true,
            previousQuantity: 3,
            unit: "piece",
            editedQuantity: 3
        ),
        "hand-edited same amount keeps the check"
    )
    check(
        GroceryCheckState.keepsCheckAfterRebuild(
            wasChecked: true,
            storedQuantity: 3,
            storedUnit: "piece",
            plannedQuantity: 5,
            plannedUnit: "piece",
            quantityIsCustom: true
        ),
        "custom rebuild compares the displayed 3, not the planned 5"
    )
    check(
        GroceryCheckState.keepsCheck(
            wasChecked: true,
            previousQuantity: 3,
            previousUnit: "piece",
            nextQuantity: 5,
            nextUnit: "piece"
        ) == false,
        "a custom row unchecks when its displayed amount changes"
    )

    let taste = UUID()
    let toTaste = mergedLine("salt", quantity: nil, unit: "toTaste", name: "Tuz")
    let tastePlan = GroceryListReconciler.plan(
        existingAuto: [
            AutoGroceryRow(id: taste, ingredientId: "salt", unit: "damak tadına", quantity: nil, isChecked: true),
        ],
        merged: toTaste
    )
    check(tastePlan.updates.first?.isChecked == true, "unchanged to-taste row stays checked")
}

private func tomatoCheck(
    meal: UUID,
    slug: String,
    sort: Int,
    checked: Bool,
    quantity: Double
) -> IngredientCheckRecord {
    IngredientCheckRecord(
        mealUUID: meal,
        recipeSlug: slug,
        ingredientId: "tomato",
        sortIndex: sort,
        isChecked: checked,
        coveredQuantity: quantity,
        unit: "piece"
    )
}

private func tomatoContribution(meal: UUID, slug: String, sort: Int, quantity: Double) -> GroceryContribution {
    GroceryContribution(
        mealUUID: meal,
        recipeSlug: slug,
        sortIndex: sort,
        ingredientId: "tomato",
        quantity: quantity,
        unit: "piece"
    )
}

private func checkIngredientCoverage() {
    let mealA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let mealB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let checkedThree = tomatoCheck(meal: mealA, slug: "recipe-a", sort: 0, checked: true, quantity: 3)
    let openTwo = tomatoCheck(meal: mealB, slug: "recipe-b", sort: 1, checked: false, quantity: 2)
    let contributions = [
        tomatoContribution(meal: mealA, slug: "recipe-a", sort: 0, quantity: 3),
        tomatoContribution(meal: mealB, slug: "recipe-b", sort: 1, quantity: 2),
    ]

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    let payload = try? encoder.encode(checkedThree)
    let restored = payload.flatMap { try? decoder.decode(IngredientCheckRecord.self, from: $0) }
    check(restored == checkedThree, "ingredient check survives a JSON round trip")

    check(
        GroceryCoverage.stillCovers(
            isChecked: true,
            coveredQuantity: 3,
            coveredUnit: "piece",
            quantity: 5,
            unit: "piece"
        ) == false,
        "a check stored at 3 does not cover a line that scaled to 5"
    )
    check(
        GroceryCoverage.stillCovers(
            isChecked: true,
            coveredQuantity: 3,
            coveredUnit: "adet",
            quantity: 3,
            unit: "piece"
        ),
        "3 adet still covers 3 piece"
    )

    let partial = GroceryCoverage.outcome(
        requiredQuantity: 5,
        requiredUnit: "piece",
        contributions: contributions,
        checks: [checkedThree, openTwo]
    )
    let partialResolved = GroceryCoverage.resolved(legacyKeepsCheck: true, outcome: partial)
    check(partial.hasCoverage, "recipe checks count toward the merged tomato row")
    check(partial.isFullyChecked == false, "3 of 5 tomatoes is not a fully checked grocery row")
    close(partial.remainingQuantity, 2, "3 checked + 2 open leaves 2 tomatoes")
    check(partialResolved.isChecked == false, "partial coverage leaves the grocery row unchecked")
    close(partialResolved.uncoveredQuantity, 2, "grocery remainder is the uncovered 2")

    let both = GroceryCoverage.outcome(
        requiredQuantity: 5,
        requiredUnit: "piece",
        contributions: contributions,
        checks: [
            checkedThree,
            tomatoCheck(meal: mealB, slug: "recipe-b", sort: 1, checked: true, quantity: 2),
        ]
    )
    let bothResolved = GroceryCoverage.resolved(legacyKeepsCheck: false, outcome: both)
    check(both.isFullyChecked, "both recipes checked covers all 5 tomatoes")
    check(both.remainingQuantity == nil, "a fully covered row has no remainder")
    check(bothResolved.isChecked && bothResolved.uncoveredQuantity == nil, "grocery row is fully checked")

    let drifted = tomatoCheck(meal: mealA, slug: "recipe-a", sort: 0, checked: true, quantity: 3)
    let driftedOutcome = GroceryCoverage.outcome(
        requiredQuantity: 7,
        requiredUnit: "piece",
        contributions: [
            tomatoContribution(meal: mealA, slug: "recipe-a", sort: 0, quantity: 5),
            tomatoContribution(meal: mealB, slug: "recipe-b", sort: 1, quantity: 2),
        ],
        checks: [drifted, openTwo]
    )
    check(driftedOutcome.didCoverSome == false, "a stale 3-piece check does not cover the new 5")
    check(driftedOutcome.isFullyChecked == false, "a drifted check does not check the grocery row")
    let driftedResolved = GroceryCoverage.resolved(legacyKeepsCheck: true, outcome: driftedOutcome)
    check(
        driftedResolved.isChecked == false && driftedResolved.uncoveredQuantity == nil,
        "a drifted check clears the grocery check instead of keeping the old one"
    )

    let custom = GroceryCoverage.outcome(
        requiredQuantity: 3,
        requiredUnit: "piece",
        contributions: contributions,
        checks: [
            checkedThree,
            tomatoCheck(meal: mealB, slug: "recipe-b", sort: 1, checked: true, quantity: 2),
        ]
    )
    check(custom.isFullyChecked, "checks that exceed a custom quantity of 3 still cover it")

    let untouched = GroceryCoverage.outcome(
        requiredQuantity: 5,
        requiredUnit: "piece",
        contributions: contributions,
        checks: []
    )
    let kept = GroceryCoverage.resolved(legacyKeepsCheck: true, outcome: untouched)
    check(untouched.hasCoverage == false && kept.isChecked && kept.uncoveredQuantity == nil, "no recipe checks keep a manual grocery check")
}

@main
struct PortionScaleChecks {
    static func main() {
        checkActiveServings()
        checkScalingSemantics()
        checkPerMealGrocerySum()
        checkReconcileKeepsChecks()
        checkQuantityChangeClearsCheck()
        checkIngredientCoverage()
        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("portion scale checks passed")
    }
}
