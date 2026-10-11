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
        // Not `yoghurt`: that spelling is a source id of `yogurt` and now
        // canonicalizes. This fixture only checks that grams and millilitres do not convert.
        line("density-check", 200, "g", nameTR: "Yoğurt"),
        line("density-check", 100, "ml", nameTR: "Yoğurt"),
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

    let density = rows("density-check", in: merged)
    check(density.count == 2 && density.allSatisfy(\.hasUnitConflict), "g and ml do not invent density \(density)")

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

    check(file.recipes.count == 325, "catalog recipe count \(file.recipes.count)")
    check(beforeIDs.count == 55, "before count \(beforeIDs.count)")
    check(afterIDs.count == 50, "after count \(afterIDs.count)")
    check(rowsBefore == 399, "rows before \(rowsBefore)")
    check(rowsAfter == 388, "rows after \(rowsAfter)")
    check(resolved == ["beef", "chicken", "lamb", "spinach", "stock"], "resolved \(resolved)")
    // Per raw catalog id. A week list then folds source ids (`tomatoes` → `tomato`);
    // see checkCanonicalIdentity. This list is not a rule that those ids stay apart.
    check(
        partial == ["fish", "oil", "onion", "potato", "tomato", "tomatoes"],
        "partial \(partial)"
    )

    let chicken = GroceryMerger.merge(linesByID["chicken"] ?? [])
    check(chicken.count == 1 && chicken[0].unit == "kg" && !chicken[0].hasUnitConflict, "catalog chicken \(chicken)")
    close(chicken.first?.quantity, 28.65, "catalog chicken kilograms")

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

private func checkAisles() {
    check(GroceryCategory.classify(ingredientId: "chicken", name: "Tavuk") == .protein, "chicken is protein")
    check(GroceryCategory.classify(ingredientId: "tomato", name: "Domates") == .produce, "tomato is produce")
    check(GroceryCategory.classify(ingredientId: "eggs", name: "Yumurta") == .dairyAndEggs, "eggs are dairy")
    check(GroceryCategory.classify(ingredientId: "flour", name: "Un") == .pantry, "flour is pantry")
    check(GroceryCategory.classify(ingredientId: "salt", name: "Tuz") == .spicesAndSauces, "salt is spice")
    check(GroceryCategory.classify(ingredientId: "water", name: "Su") == .other, "water is other")
    check(GroceryCategory.classify(ingredientId: "manual:1", name: "Süt") == .dairyAndEggs, "manual milk")
    check(GroceryCategory.classify(ingredientId: "manual:2", name: "Bilinmeyen") == .other, "manual unknown")
    check(GroceryCategory.knownCategory(ingredientId: "black-pepper") == .spicesAndSauces, "hyphenated pepper id")

    let url = URL(fileURLWithPath: "MealRoutine/Recipes/recipes.v1.json")
    guard let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(RecipeCatalogFile.self, from: data) else {
        check(false, "catalog json should decode for aisle coverage")
        return
    }
    var missing: [String] = []
    for recipe in file.recipes {
        for ingredient in recipe.ingredients where GroceryCategory.knownCategory(ingredientId: ingredient.id) == nil {
            missing.append(ingredient.id)
        }
    }
    check(missing.isEmpty, "catalog ids missing an aisle: \(Set(missing).sorted())")
    check(
        GroceryCategory.sectionOrder.map(\.title) == [
            "Sebze ve meyve", "Protein", "Süt ve yumurta", "Kiler", "Baharat ve soslar", "Diğer"
        ],
        "aisle titles"
    )
}

private func checkGroupingAndQuantityEdits() {
    let rows = [
        GroceryGroupInput(name: "Tuz", category: .spicesAndSauces, isChecked: false),
        GroceryGroupInput(name: "Tavuk", category: .protein, isChecked: false),
        GroceryGroupInput(name: "Domates", category: .produce, isChecked: true),
        GroceryGroupInput(name: "Süt", category: .dairyAndEggs, isChecked: false),
        GroceryGroupInput(name: "Un", category: .pantry, isChecked: false),
        GroceryGroupInput(name: "Su", category: .other, isChecked: true),
    ]
    check(
        GroceryListGrouping.openCategories(in: rows) == [.protein, .dairyAndEggs, .pantry, .spicesAndSauces],
        "open aisles keep market order and drop checked rows"
    )
    check(GroceryQuantityEdit.parse("1,25") == Optional(1.25), "comma decimal")
    check(GroceryQuantityEdit.parse("2") == Optional(2.0), "whole number")
    check(GroceryQuantityEdit.parse("  ") == nil, "blank quantity")
    check(GroceryQuantityEdit.parse("abc") == nil, "non numeric quantity")
    check(GroceryQuantityEdit.parse("-1") == nil, "negative quantity")
    check(
        GroceryQuantityEdit.quantityToStore(planned: 1.25, edited: 2, isCustom: true) == Optional(2.0),
        "custom amount survives rebuild"
    )
    check(
        GroceryQuantityEdit.quantityToStore(planned: 1.25, edited: 2, isCustom: false) == Optional(1.25),
        "planned amount stays until the row is edited"
    )
}

private func checkEveningLabels() {
    check(EveningCountOptions.values == [1, 2, 3, 4, 5, 6, 7], "evening choices stay 1...7")
    check(EveningCountOptions.label(1) == "1 akşam", "one evening label")
    check(EveningCountOptions.label(3) == "3 akşam", "three evening label")
    check(EveningCountOptions.label(5) == "5 akşam", "five evening label")
    check(EveningCountOptions.label(7) == "7 akşam", "seven evening label")
    check(!EveningCountOptions.label(4).contains("Evening"), "labels stay Turkish")
}

/// 2026-10-11: the user approved merging on the dictionary canonical id.
/// `tomatoes` joins `tomato`. Display text does not. `cherry-tomato` stays apart.
private func checkCanonicalIdentity() {
    let url = URL(fileURLWithPath: "MealRoutine/Recipes/ingredients.v1.json")
    guard let data = try? Data(contentsOf: url), let dictionary = try? IngredientDictionary(data: data) else {
        check(false, "ingredients.v1.json should load for canonical merge")
        return
    }
    let merged = GroceryMerger.merge([
        line("tomato", 6, "piece", nameTR: "Domates"),
        line("tomatoes", 2, "adet", nameTR: "Domates"),
        line("cherry-tomato", 4, "piece", nameTR: "Cherry domates"),
    ], dictionary: dictionary)
    let tomato = rows("tomato", in: merged)
    check(tomato.count == 1, "tomato and tomatoes are one plan row \(merged)")
    close(tomato.first?.quantity, 8, "6 + 2 tomatoes")
    check(tomato.first?.nameTR == "Domates", "canonical name \(tomato.first?.nameTR ?? "")")
    check(rows("tomatoes", in: merged).isEmpty, "alias id is not a second row")
    check(rows("cherry-tomato", in: merged).count == 1, "cherry-tomato stays separate")
    check(
        GroceryMerger.rowIdentity(ingredientId: "tomatoes", unit: "piece", dictionary: dictionary)
            == GroceryMerger.rowIdentity(ingredientId: "tomato", unit: "adet", dictionary: dictionary),
        "alias identity"
    )
    check(
        GroceryMerger.rowIdentity(ingredientId: "cherry-tomato", unit: "piece", dictionary: dictionary)
            != GroceryMerger.rowIdentity(ingredientId: "tomato", unit: "piece", dictionary: dictionary),
        "cherry identity"
    )
    check(
        GroceryCategory.classify(ingredientId: "pantry-auto:tomatoes|unit:piece", name: "Domates") == .produce,
        "aisle uses the canonical id inside a pantry key"
    )

    let plan = UUID()
    let shortfall = UUID()
    let typed = UUID()
    let threshold = UUID()
    let cards = GroceryCardGrouper.group([
        GroceryCardInput(id: plan, ingredientId: "tomatoes", name: "Domates", quantity: 6, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: false, sourceRaw: GroceryLineSource.plan.rawValue, remainingDetail: nil),
        GroceryCardInput(id: shortfall, ingredientId: "pantry-auto:tomato|unit:piece", name: "Domates", quantity: 1, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: GroceryLineSource.shortfall.rawValue, remainingDetail: nil),
        GroceryCardInput(id: threshold, ingredientId: "pantry-auto:tomato|family:mass", name: "Domates", quantity: 200, unit: "g", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: GroceryLineSource.threshold.rawValue, remainingDetail: nil),
        GroceryCardInput(id: typed, ingredientId: "manual:\(UUID().uuidString)", name: "Domates", quantity: 2, unit: "piece", hasUnitConflict: false, isChecked: true, isManual: true, sourceRaw: GroceryLineSource.typed.rawValue, remainingDetail: nil),
    ], dictionary: dictionary)
    let piece = cards.filter { $0.id.hasSuffix("unit:piece") }
    check(piece.count == 1, "piece rows share one card \(cards.map(\.id))")
    check(piece.first?.parts.count == 3, "plan, shortfall and typed stay separate parts")
    check(piece.first?.isMixed == true, "one checked part is a mixed card")
    check(piece.first?.isFullyChecked == false, "mixed card is not fully checked")
    check(piece.first?.breakdown == "Plan: 6 adet · Evdekiler eksiği: 1 adet · Elle eklendi: 2 adet", "breakdown \(piece.first?.breakdown ?? "")")
    check(!((piece.first?.breakdown ?? "").contains("8")), "breakdown does not sum plan and shortfall")
    let mass = cards.filter { $0.id.hasSuffix("family:mass") }
    check(mass.count == 1 && mass.first?.parts.first?.source == .threshold, "threshold stays on its own bucket \(cards.map(\.breakdown))")
    check(mass.first?.parts.first?.label == "Eşik: 200 g", "threshold label \(mass.first?.breakdown ?? "")")
    let cherryCard = GroceryCardGrouper.group([
        GroceryCardInput(id: UUID(), ingredientId: "manual:\(UUID().uuidString)", name: "Cherry domates", quantity: 1, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: "", remainingDetail: nil),
    ], dictionary: dictionary)
    check(cherryCard.first?.id.hasPrefix("cherry-tomato|") == true, "typed cherry name binds to cherry-tomato, not tomato")
}

/// 2026-10-11 follow-up: rows saved before the canonical key were still two
/// “Evdekiler eksiği” parts. A shortfall is a set, so 1 and 2 stay 2, not 3.
private func checkLegacyShortfallCollapse() {
    let url = URL(fileURLWithPath: "MealRoutine/Recipes/ingredients.v1.json")
    guard let data = try? Data(contentsOf: url), let dictionary = try? IngredientDictionary(data: data) else {
        check(false, "ingredients.v1.json should load for shortfall collapse")
        return
    }
    let sheet = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    let bitti = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    let typed = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
    let cook = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
    let plan = UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!
    let rows = [
        LegacyGroceryRow(id: sheet, ingredientId: "pantry-auto:tomatoes|piece", quantity: 1, unit: "piece", isChecked: false, isManual: true, sourceRaw: ""),
        LegacyGroceryRow(id: bitti, ingredientId: "tomatoes", quantity: 2, unit: "adet", isChecked: true, isManual: true, sourceRaw: ""),
        LegacyGroceryRow(id: typed, ingredientId: "manual:\(typed.uuidString)", quantity: 2, unit: "piece", isChecked: false, isManual: true, sourceRaw: ""),
        LegacyGroceryRow(id: cook, ingredientId: "pantry-cook:meal-1:tomatoes|piece", quantity: 1, unit: "piece", isChecked: false, isManual: true, sourceRaw: GroceryLineSource.shortfall.rawValue),
        LegacyGroceryRow(id: plan, ingredientId: "tomato", quantity: 6, unit: "piece", isChecked: false, isManual: false, sourceRaw: ""),
    ]
    let collapsed = GroceryShortfallCollapse.plan(rows, dictionary: dictionary)
    check(collapsed.updates.count == 1, "one shortfall identity \(collapsed.updates)")
    let update = collapsed.updates.first
    check(update?.ingredientId == "pantry-auto:tomato|unit:piece", "canonical key \(update?.ingredientId ?? "")")
    check(update?.quantity == 2, "larger set is kept, not the sum \(update?.quantity ?? -1)")
    check(update?.isChecked == true, "check survives when that amount was checked")
    check(update?.keepID == bitti, "the larger row is the survivor")
    check(update?.deleteIDs == [sheet], "the smaller legacy key is removed \(update?.deleteIDs ?? [])")
    check(update?.sourceRaw == GroceryLineSource.shortfall.rawValue, "legacy empty source is Evdekiler eksiği")
    check(collapsed.cookGapIDs == [cook], "cook gap is retitled, not merged into the shortfall")
    check(!collapsed.updates.contains { $0.deleteIDs.contains(typed) || $0.keepID == typed }, "typed manual: row stays Elle eklendi")
    check(!collapsed.updates.contains { $0.keepID == plan }, "plan row is not a shortfall")

    let checkedSmaller = GroceryShortfallCollapse.plan([
        LegacyGroceryRow(id: sheet, ingredientId: "pantry-auto:tomato|piece", quantity: 1, unit: "piece", isChecked: true, isManual: true, sourceRaw: ""),
        LegacyGroceryRow(id: bitti, ingredientId: "pantry-auto:tomatoes|adet", quantity: 2, unit: "adet", isChecked: false, isManual: true, sourceRaw: ""),
    ], dictionary: dictionary)
    check(checkedSmaller.updates.first?.quantity == 2, "unchecked larger set wins")
    check(checkedSmaller.updates.first?.isChecked == false, "a check on a different amount is not moved")

    let mass = GroceryShortfallCollapse.plan([
        LegacyGroceryRow(id: sheet, ingredientId: "pantry-auto:tomato|g", quantity: 200, unit: "g", isChecked: false, isManual: true, sourceRaw: GroceryLineSource.threshold.rawValue),
        LegacyGroceryRow(id: bitti, ingredientId: "pantry-auto:tomatoes|kg", quantity: 1, unit: "kg", isChecked: false, isManual: true, sourceRaw: ""),
    ], dictionary: dictionary)
    check(mass.updates.first?.quantity == 1 && mass.updates.first?.unit == "kg", "1 kg beats 200 g \(mass.updates.first?.quantity ?? -1) \(mass.updates.first?.unit ?? "")")
    check(mass.updates.first?.sourceRaw == GroceryLineSource.shortfall.rawValue, "the row that supplies the amount supplies the label")

    let canonical = "pantry-auto:tomato|unit:piece"
    let legacy = "pantry-auto:tomatoes|piece"
    let both = GroceryShortfallCollapse.boardSync(
        canonicalKey: canonical,
        existingKeys: [legacy, canonical, "tomato|piece"],
        deletedIDs: [sheet],
        dictionary: dictionary
    )
    check(both.wireKey == canonical, "canonical server key is kept when it exists \(both.wireKey)")
    check(both.removeKeys.contains(legacy), "legacy pantry-auto key is retired")
    check(both.removeKeys.contains("manual:\(sheet.uuidString)"), "deleted row check key is retired")
    check(!both.removeKeys.contains(canonical), "the wire key is not removed")
    check(!both.removeKeys.contains("tomato|piece"), "plan key is not a shortfall key")
    let onlyLegacy = GroceryShortfallCollapse.boardSync(
        canonicalKey: canonical,
        existingKeys: [legacy],
        deletedIDs: [],
        dictionary: dictionary
    )
    check(onlyLegacy.wireKey == legacy && onlyLegacy.removeKeys.isEmpty, "a lone legacy key is updated in place \(onlyLegacy)")

    let cards = GroceryCardGrouper.group([
        GroceryCardInput(id: sheet, ingredientId: "pantry-auto:tomatoes|piece", name: "Domates", quantity: 1, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: "", remainingDetail: nil),
        GroceryCardInput(id: bitti, ingredientId: "tomatoes", name: "Domates", quantity: 2, unit: "adet", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: "", remainingDetail: nil),
        GroceryCardInput(id: cook, ingredientId: "pantry-cook:meal-1:tomatoes|piece", name: "Domates", quantity: 1, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: true, sourceRaw: GroceryLineSource.shortfall.rawValue, remainingDetail: nil),
        GroceryCardInput(id: plan, ingredientId: "tomato", name: "Domates", quantity: 6, unit: "piece", hasUnitConflict: false, isChecked: false, isManual: false, sourceRaw: "", remainingDetail: nil),
    ], dictionary: dictionary)
    let card = cards.first { $0.id.hasSuffix("unit:piece") }
    let labels = card?.parts.map(\.source) ?? []
    check(labels.filter { $0 == .shortfall }.count == 1, "one Evdekiler eksiği part \(labels)")
    check(Set(labels).count == labels.count, "no repeated source label \(labels)")
    let shortfall = card?.parts.first { $0.source == .shortfall }
    check(shortfall?.label == "Evdekiler eksiği: 2 adet", "shortfall shows the larger set \(shortfall?.label ?? "")")
    check(shortfall?.memberIDs.count == 2, "both stored rows stay reachable until reconcile deletes one")
    check(!(shortfall?.label.contains("3") ?? false), "shortfall label is not a sum")
    check(card?.parts.first { $0.source == .cookGap }?.label == "Pişirme eksiği: 1 adet", "cook gap has its own label \(card?.breakdown ?? "")")
    let repeated = Dictionary(grouping: card?.parts ?? [], by: \.source.title)
    check(repeated.values.allSatisfy { $0.count == 1 }, "a card never has two parts with the same source label")
}

/// A completed personal recipe uses the same aggregation as the catalog.
/// `import:mercimek` is the dictionary name, so the row is `lentils` at the
/// entered amount. The optional suffix is not that ingredient.
private func checkPersonalRecipeIdentity() {
    let url = URL(fileURLWithPath: "MealRoutine/Recipes/ingredients.v1.json")
    guard let data = try? Data(contentsOf: url), let dictionary = try? IngredientDictionary(data: data) else {
        check(false, "ingredients.v1.json should load for personal grocery identity")
        return
    }
    let merged = GroceryMerger.merge([
        line("import:mercimek", 2, "g", nameTR: "mercimek"),
        line("import:tuz|optional", 1, "tsp", nameTR: "tuz (isteğe bağlı)"),
        line("import:not-a-dictionary-name", 4, "piece", nameTR: "Özel malzeme"),
    ], dictionary: dictionary)
    let lentils = rows("lentils", in: merged)
    check(lentils.count == 1, "mercimek joins the dictionary id \(merged.map(\.ingredientId))")
    close(lentils.first?.quantity, 2, "entered mercimek amount is kept")
    check(lentils.first?.nameTR == "Mercimek", "dictionary name \(lentils.first?.nameTR ?? "")")
    check(rows("import:mercimek", in: merged).isEmpty, "raw import id is not a second row")
    let optional = merged.filter { $0.ingredientId.hasSuffix("|optional") }
    check(optional.count == 1, "optional personal line stays its own row \(merged.map(\.ingredientId))")
    close(optional.first?.quantity, 1, "optional amount is kept")
    check(rows("salt", in: merged).isEmpty, "optional tuz is not the salt row")
    let custom = rows("import:not-a-dictionary-name", in: merged)
    check(custom.count == 1, "unknown personal name stays on its import id")
    close(custom.first?.quantity, 4, "unknown personal amount is kept")
    check(custom.first?.nameTR == "Özel malzeme", "unknown personal name is the typed name")
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

        checkAisles()
        checkGroupingAndQuantityEdits()
        checkEveningLabels()
        checkCanonicalIdentity()
        checkLegacyShortfallCollapse()
        checkPersonalRecipeIdentity()

        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("grocery merge checks passed")
    }
}
