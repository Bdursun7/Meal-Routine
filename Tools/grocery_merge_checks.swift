import Foundation

/// Focused checks for grocery unit folding and merging. Compile with the
/// Foundation-only sources (no SwiftData, no Xcode):
///
///   Tools/run_grocery_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func line(
    _ id: String,
    _ quantity: Double?,
    _ unit: String,
    nameTR: String = "",
    nameEN: String = ""
) -> GrocerySourceLine {
    GrocerySourceLine(
        ingredientId: id,
        nameTR: nameTR,
        nameEN: nameEN,
        quantity: quantity,
        unit: unit
    )
}

private func rows(_ id: String, in merged: [MergedGroceryLine]) -> [MergedGroceryLine] {
    merged.filter { $0.ingredientId == id }
}

private func close(_ lhs: Double?, _ rhs: Double, _ message: String) {
    guard let lhs else {
        check(false, "\(message) was nil")
        return
    }
    check(abs(lhs - rhs) < 0.000_1, "\(message) got \(lhs) expected \(rhs)")
}

private func checkSynonyms() {
    check(GroceryMerger.normalize("GR") == "g", "GR should be g")
    check(GroceryMerger.normalize("gram") == "g", "gram should be g")
    check(GroceryMerger.normalize("mL") == "ml", "mL should be ml")
    check(GroceryMerger.normalize("Litre") == "l", "Litre should be l")
    check(GroceryMerger.normalize("adet") == "piece", "adet should be piece")
    check(GroceryMerger.normalize("Yemek Kaşığı") == "tbsp", "Yemek Kaşığı should be tbsp")
    check(GroceryMerger.normalize("YEMEK KAŞIĞI") == "tbsp", "YEMEK KAŞIĞI should be tbsp")
    check(GroceryMerger.normalize("tatlı kaşığı") == "tsp", "tatlı kaşığı should be tsp")
    check(GroceryMerger.normalize("diş") == "clove", "diş should be clove")
    check(GroceryMerger.normalize("tutam") == "pinch", "tutam should be pinch")
    check(GroceryMerger.normalize("damak tadına") == "toTaste", "damak tadına should be toTaste")
    check(GroceryMerger.normalize("to taste") == "toTaste", "to taste should be toTaste")
    check(GroceryMerger.normalize("dal") == "sprig", "dal should be sprig")
    check(GroceryMerger.normalize("dilim") == "slice", "dilim should be slice")
    check(UnitLabels.turkish("kg") == "kg", "kg label")
    check(UnitLabels.turkish("piece") == "adet", "piece label")
    check(UnitLabels.turkish("tbsp") == "yemek kaşığı", "tbsp label")

    let merged = GroceryMerger.merge([
        line("salt", 200, "GR", nameTR: "Tuz"),
        line("salt", 300, "gram", nameTR: "Tuz"),
        line("oil", 2, "yemek kaşığı", nameTR: "Yağ"),
        line("oil", 1, "tbsp", nameTR: "Yağ"),
        line("egg", 2, "adet", nameTR: "Yumurta"),
        line("egg", 3, "pieces", nameTR: "Yumurta"),
    ])
    let salt = rows("salt", in: merged)
    check(salt.count == 1 && !salt[0].hasUnitConflict, "gram spellings should be one row")
    close(salt.first?.quantity, 500, "gram sum")
    check(salt.first?.unit == "g", "gram display unit \(salt.first?.unit ?? "")")

    let oil = rows("oil", in: merged)
    check(oil.count == 1 && oil[0].unit == "tbsp", "spoon spellings \(oil)")
    close(oil.first?.quantity, 3, "spoon sum")

    let egg = rows("egg", in: merged)
    check(egg.count == 1 && egg[0].unit == "piece", "piece spellings \(egg)")
    close(egg.first?.quantity, 5, "piece sum")
    let detail = QuantityFormat.quantityAndUnit(quantity: 5, unit: "piece")
    check(detail.contains("adet"), "display should prefer the Turkish piece label, got \(detail)")
}

private func checkConversions() {
    let merged = GroceryMerger.merge([
        line("chicken", 250, "g", nameTR: "Tavuk"),
        line("chicken", 1, "kg", nameTR: "Tavuk"),
        line("stock", 250, "mL", nameTR: "Et suyu"),
        line("stock", 1, "L", nameTR: "Et suyu"),
        line("onion", 2, "piece", nameTR: "Soğan"),
        line("onion", 150, "g", nameTR: "Soğan"),
        line("onion", 0.5, "kg", nameTR: "Soğan"),
        line("spice", 1, "tbsp", nameTR: "Kimyon"),
        line("spice", 2, "tsp", nameTR: "Kimyon"),
        line("salt", nil, "toTaste", nameTR: "Tuz"),
        line("salt", 5, "g", nameTR: "Tuz"),
        line("yoghurt", 200, "g", nameTR: "Yoğurt"),
        line("yoghurt", 100, "ml", nameTR: "Yoğurt"),
    ])

    let chicken = rows("chicken", in: merged)
    check(chicken.count == 1 && !chicken[0].hasUnitConflict, "g+kg should be one row \(chicken)")
    check(chicken.first?.unit == "kg", "250 g + 1 kg should display as kg")
    close(chicken.first?.quantity, 1.25, "250 g + 1 kg")

    let stock = rows("stock", in: merged)
    check(stock.count == 1 && stock[0].unit == "l", "ml+l \(stock)")
    close(stock.first?.quantity, 1.25, "250 ml + 1 l")

    let onion = rows("onion", in: merged)
    check(onion.count == 2 && onion.allSatisfy(\.hasUnitConflict), "piece stays apart from mass \(onion)")
    let onionMass = onion.first { $0.unit == "g" || $0.unit == "kg" }
    close(onionMass?.quantity, 650, "150 g + 0.5 kg stays in grams")
    check(onionMass?.unit == "g", "sub-kilogram mix displays as g, got \(onionMass?.unit ?? "")")
    check(onion.contains { $0.unit == "piece" && $0.quantity == 2 }, "onion piece row \(onion)")

    let spice = rows("spice", in: merged)
    check(spice.count == 2 && spice.allSatisfy(\.hasUnitConflict), "tbsp and tsp stay apart \(spice)")

    let salt = rows("salt", in: merged)
    check(salt.count == 2 && salt.allSatisfy(\.hasUnitConflict), "toTaste stays apart from grams \(salt)")
    check(salt.contains { $0.unit == "toTaste" && $0.quantity == nil }, "toTaste quantity stays nil \(salt)")
    check(salt.contains { $0.unit == "g" && $0.quantity == 5 }, "measured salt stays 5 g \(salt)")

    let yoghurt = rows("yoghurt", in: merged)
    check(yoghurt.count == 2 && yoghurt.allSatisfy(\.hasUnitConflict), "g and ml do not invent density \(yoghurt)")

    let onlyGrams = GroceryMerger.merge([
        line("flour", 800, "g"),
        line("flour", 400, "g"),
    ])
    check(onlyGrams.count == 1 && onlyGrams[0].unit == "g", "homogeneous grams stay grams \(onlyGrams)")
    close(onlyGrams.first?.quantity, 1_200, "homogeneous gram sum")

    let onlyKilos = GroceryMerger.merge([
        line("lamb", 1.2, "kg"),
        line("lamb", 0.4, "kilo"),
    ])
    check(onlyKilos.count == 1 && onlyKilos[0].unit == "kg", "homogeneous kilos stay kilos \(onlyKilos)")
    close(onlyKilos.first?.quantity, 1.6, "homogeneous kilo sum")
}

private func checkScaling() {
    let household = 4
    let nasi = PortionScaler.scale(quantity: 250, scaling: "linear", baseServings: 4, householdSize: household)
    let adobo = PortionScaler.scale(quantity: 1, scaling: "linear", baseServings: 4, householdSize: household)
    let merged = GroceryMerger.merge([
        line("chicken", nasi, "g", nameTR: "Tavuk", nameEN: "Chicken"),
        line("chicken", adobo, "kg", nameTR: "Tavuk", nameEN: "Chicken"),
    ])
    check(merged.count == 1 && merged[0].unit == "kg" && !merged[0].hasUnitConflict, "scaled week merge \(merged)")
    close(merged.first?.quantity, 1.25, "household 4 nasi+adobo")
    check(merged.first?.nameTR == "Tavuk", "Turkish name wins")

    let smallHousehold = 2
    let small = GroceryMerger.merge([
        line("chicken", PortionScaler.scale(quantity: 250, scaling: "linear", baseServings: 4, householdSize: smallHousehold), "g"),
        line("chicken", PortionScaler.scale(quantity: 1, scaling: "linear", baseServings: 4, householdSize: smallHousehold), "kg"),
    ])
    check(small.count == 1 && small[0].unit == "g", "household 2 stays under a kilogram \(small)")
    close(small.first?.quantity, 625, "household 2 chicken grams")

    let damped = PortionScaler.scale(quantity: 4, scaling: "damped", baseServings: 4, householdSize: 1)
    close(damped, 2, "damped household 1 of base 4")
    let fixed = PortionScaler.scale(quantity: 4, scaling: "fixed", baseServings: 4, householdSize: 8)
    close(fixed, 4, "fixed ignores household")
    let linear = PortionScaler.scale(quantity: 2, scaling: "linear", baseServings: 4, householdSize: 8)
    close(linear, 4, "linear doubles")

    let scaledSpice = GroceryMerger.merge([
        line("cumin", damped, "tsp"),
        line("cumin", fixed, "tsp"),
    ])
    close(scaledSpice.first?.quantity, 6, "scaled spoon quantities still sum when the unit matches")
}

private func legacyUnit(_ unit: String) -> String {
    unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func checkCatalog() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("MealRoutine/Recipes/recipes.v1.json")
    let data = try Data(contentsOf: url)
    let file = try JSONDecoder().decode(RecipeCatalogFile.self, from: data)

    var linesByID: [String: [GrocerySourceLine]] = [:]
    var lineCount = 0
    for recipe in file.recipes {
        for ingredient in recipe.ingredients {
            lineCount += 1
            linesByID[ingredient.id, default: []].append(
                GrocerySourceLine(
                    ingredientId: ingredient.id,
                    nameTR: ingredient.name.tr ?? "",
                    nameEN: ingredient.name.en ?? "",
                    quantity: ingredient.quantity,
                    unit: ingredient.unit
                )
            )
        }
    }

    var beforeIDs: [String] = []
    var afterIDs: [String] = []
    var resolved: [String] = []
    var partial: [String] = []
    var rowsBefore = 0
    var rowsAfter = 0

    for (id, lines) in linesByID {
        let rawUnits = Set(lines.map { legacyUnit($0.unit) })
        rowsBefore += rawUnits.count
        let merged = GroceryMerger.merge(lines)
        rowsAfter += merged.count
        let conflictedBefore = rawUnits.count > 1
        let conflictedAfter = merged.contains(where: \.hasUnitConflict)
        if conflictedBefore { beforeIDs.append(id) }
        if conflictedAfter { afterIDs.append(id) }
        if conflictedBefore, !conflictedAfter { resolved.append(id) }
        if conflictedBefore, conflictedAfter, merged.count < rawUnits.count {
            partial.append(id)
        }
        if conflictedAfter {
            check(merged.allSatisfy(\.hasUnitConflict), "\(id) conflict flag should mark every remaining row")
        }
    }

    beforeIDs.sort()
    afterIDs.sort()
    resolved.sort()
    partial.sort()

    print("catalog recipes: \(file.recipes.count)")
    print("ingredient lines: \(lineCount)")
    print("unique ingredient ids: \(linesByID.count)")
    print("multi-unit conflict ids before: \(beforeIDs.count)")
    print("multi-unit conflict ids after: \(afterIDs.count)")
    print("catalog-wide rows before: \(rowsBefore)")
    print("catalog-wide rows after: \(rowsAfter)")
    print("fully resolved ids (\(resolved.count)): \(resolved.joined(separator: ", "))")
    print("partially merged ids (\(partial.count)): \(partial.joined(separator: ", "))")

    check(file.recipes.count == 125, "catalog recipe count \(file.recipes.count)")
    check(beforeIDs.count == 55, "before count \(beforeIDs.count)")
    check(afterIDs.count == 50, "after count \(afterIDs.count)")
    check(rowsBefore == 382, "rows before \(rowsBefore)")
    check(rowsAfter == 371, "rows after \(rowsAfter)")
    check(resolved == ["beef", "chicken", "lamb", "spinach", "stock"], "resolved \(resolved)")
    check(
        partial == ["fish", "oil", "onion", "potato", "tomato", "tomatoes"],
        "partial \(partial)"
    )

    let chicken = GroceryMerger.merge(linesByID["chicken"] ?? [])
    check(chicken.count == 1 && chicken[0].unit == "kg" && !chicken[0].hasUnitConflict, "catalog chicken \(chicken)")
    close(chicken.first?.quantity, 14.95, "catalog chicken kilograms")

    let stock = GroceryMerger.merge(linesByID["stock"] ?? [])
    check(stock.count == 1 && stock[0].unit == "l", "catalog stock \(stock)")
    close(stock.first?.quantity, 7.45, "catalog stock litres")

    guard let nasi = file.recipes.first(where: { $0.id == "nasi-goreng" }),
          let adobo = file.recipes.first(where: { $0.id == "adobo" }) else {
        check(false, "nasi-goreng and adobo should be in the catalog")
        return
    }
    var week: [GrocerySourceLine] = []
    for recipe in [nasi, adobo] {
        for ingredient in recipe.ingredients where ingredient.id == "chicken" {
            week.append(
                GrocerySourceLine(
                    ingredientId: ingredient.id,
                    nameTR: ingredient.name.tr ?? "",
                    nameEN: ingredient.name.en ?? "",
                    quantity: PortionScaler.scale(
                        quantity: ingredient.quantity,
                        scaling: ingredient.scaling,
                        baseServings: recipe.baseServings,
                        householdSize: 4
                    ),
                    unit: ingredient.unit
                )
            )
        }
    }
    let weekMerged = GroceryMerger.merge(week)
    check(weekMerged.count == 1 && weekMerged[0].unit == "kg", "nasi goreng + adobo \(weekMerged)")
    close(weekMerged.first?.quantity, 1.25, "nasi goreng 250 g + adobo 1 kg")
    let shown = QuantityFormat.quantityAndUnit(quantity: weekMerged.first?.quantity, unit: weekMerged.first?.unit ?? "")
    check(shown.contains("kg"), "week line should show kg, got \(shown)")
    check(shown.contains("1,25") || shown.contains("1.25"), "week line should show 1.25, got \(shown)")
}

@main
struct GroceryMergeChecks {
    static func main() {
        checkSynonyms()
        checkConversions()
        checkScaling()
        do {
            try checkCatalog()
        } catch {
            failures += 1
            fputs("FAIL catalog \(error)\n", stderr)
        }

        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("grocery merge checks passed")
    }
}
