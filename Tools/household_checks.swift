import Foundation

private func checkPlanKeys() {
    let dictionary = IngredientDictionary(entries: [
        IngredientEntry(id: "tomato", name: "Domates", synonyms: ["İri domates"], sourceIds: ["tomatoes"]),
        IngredientEntry(id: "cherry-tomato", name: "Cherry domates", sourceIds: []),
    ])
    let canonical = HouseholdGroceryKey.make(
        ingredientId: "tomatoes", unit: "adet", isManual: false, uuid: UUID(), dictionary: dictionary
    )
    if canonical != "tomato|piece" {
        fputs("FAIL plan sync key \(canonical)\n", stderr)
        exit(1)
    }
    if !HouseholdGroceryKey.samePlanIdentity("tomatoes|piece", "tomato|piece", dictionary: dictionary) {
        fputs("FAIL legacy tomatoes key should match tomato\n", stderr)
        exit(1)
    }
    if HouseholdGroceryKey.samePlanIdentity("cherry-tomato|piece", "tomato|piece", dictionary: dictionary) {
        fputs("FAIL cherry-tomato must stay separate\n", stderr)
        exit(1)
    }
    if HouseholdGroceryKey.samePlanIdentity("pantry-auto:tomato|unit:piece", "tomato|piece", dictionary: dictionary) {
        fputs("FAIL pantry shortfall must not match the plan key\n", stderr)
        exit(1)
    }
    let manual = UUID()
    if HouseholdGroceryKey.make(ingredientId: "tomato", unit: "piece", isManual: true, uuid: manual, dictionary: dictionary) != "manual:\(manual.uuidString)" {
        fputs("FAIL typed row keeps manual uuid key\n", stderr)
        exit(1)
    }
    let shortfall = "pantry-auto:tomato|unit:piece"
    if HouseholdGroceryKey.make(ingredientId: shortfall, unit: "piece", isManual: true, uuid: UUID(), dictionary: dictionary) != shortfall {
        fputs("FAIL shortfall check must keep the server key\n", stderr)
        exit(1)
    }
    if !HouseholdGroceryPreserve.survivesWeekRebuild(ingredientId: shortfall, isManual: true)
        || !HouseholdGroceryPreserve.survivesWeekRebuild(ingredientId: "pantry-cook:meal:tomato|unit:piece", isManual: false)
        || !HouseholdGroceryPreserve.survivesWeekRebuild(ingredientId: "manual:\(manual.uuidString)", isManual: true)
        || HouseholdGroceryPreserve.survivesWeekRebuild(ingredientId: "tomato", isManual: false) {
        fputs("FAIL week rebuild must keep extras and drop plan rows\n", stderr)
        exit(1)
    }
    let wireID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let materialized = SharedGroceryMaterializer.rows(from: [
        SharedGroceryWire(id: wireID, itemKey: shortfall, quantity: 0.6, unit: "kg", lineSource: "shortfall", isChecked: true, revision: 2),
        SharedGroceryWire(id: wireID, itemKey: "tomato|piece", quantity: 2, unit: nil, lineSource: nil, isChecked: false, revision: 1),
    ], dictionary: dictionary)
    if materialized.count != 1 || materialized[0].quantity != 0.6 || materialized[0].unit != "kg" || materialized[0].isChecked != true || materialized[0].sourceRaw != "shortfall" {
        fputs("FAIL shared shortfall must materialize with decimal quantity\n", stderr)
        exit(1)
    }
}

@main
struct HouseholdChecks {
    static func main() {
        checkPlanKeys()
        let failures = HouseholdLogicChecks.runAll()
        if failures.isEmpty {
            print("household checks passed")
        } else {
            for failure in failures {
                fputs("\(failure)\n", stderr)
            }
            exit(1)
        }
    }
}
