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
