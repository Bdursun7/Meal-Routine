import Foundation

struct GrocerySourceLine: Equatable, Sendable {
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
}

struct MergedGroceryLine: Equatable, Sendable, Identifiable {
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
    var hasUnitConflict: Bool

    var id: String { "\(ingredientId)|\(unit)" }
}

/// Groups shopping lines by UniTools ingredient id.
///
/// Equivalent spellings (`g` / `gr` / `gram`, `adet` / `piece`, `yemek kaşığı` / `tbsp`)
/// sum into one row. Gram converts with kilogram, and millilitre with litre.
/// Anything else with the same id stays on its own row and is flagged.
enum GroceryMerger {
    static func merge(_ lines: [GrocerySourceLine]) -> [MergedGroceryLine] {
        let grouped = Dictionary(grouping: lines, by: \.ingredientId)
        var merged: [MergedGroceryLine] = []
        merged.reserveCapacity(grouped.count)

        for (ingredientId, group) in grouped {
            let parsed = group.map { line in
                (line: line, unit: UnitNormalization.parse(line.unit))
            }
            let buckets = Dictionary(grouping: parsed) { item in
                bucketKey(for: item.unit)
            }
            let hasConflict = buckets.count > 1

            for key in buckets.keys.sorted() {
                let unitLines = buckets[key] ?? []
                let combined = UnitNormalization.combine(
                    quantities: unitLines.map(\.line.quantity),
                    units: unitLines.map(\.unit)
                )
                let nameTR = unitLines.first(where: { !$0.line.nameTR.isEmpty })?.line.nameTR
                    ?? unitLines.first?.line.nameEN
                    ?? ingredientId
                let nameEN = unitLines.first(where: { !$0.line.nameEN.isEmpty })?.line.nameEN ?? ""
                merged.append(
                    MergedGroceryLine(
                        ingredientId: ingredientId,
                        nameTR: nameTR,
                        nameEN: nameEN,
                        quantity: roundedQuantity(combined.quantity),
                        unit: combined.code,
                        hasUnitConflict: hasConflict
                    )
                )
            }
        }

        return merged.sorted { lhs, rhs in
            let nameOrder = lhs.nameTR.localizedStandardCompare(rhs.nameTR)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.unit < rhs.unit
        }
    }

    /// Thousandths, the same snap as pantry and unit conversion.
    /// `0.1 + 0.2` becomes `0.3`. 125 g + 1 kg stays `1.125` kg.
    static func roundedQuantity(_ quantity: Double?) -> Double? {
        guard let quantity else { return nil }
        return (quantity * 1_000).rounded() / 1_000
    }

    /// Canonical unit code. Safe to store and to compare across rebuilds.
    static func normalize(_ unit: String) -> String {
        UnitNormalization.parse(unit).code
    }

    /// Identity of one automatic shopping row across rebuilds.
    ///
    /// Mass (`g` / `kg`) and volume (`ml` / `l`) share an identity, so a checked
    /// gram row can become kilograms when the scaled total crosses that line.
    /// Every other unit stays on its own canonical code.
    static func rowIdentity(ingredientId: String, unit: String) -> String {
        let parsed = UnitNormalization.parse(unit)
        return "\(ingredientId)|\(bucketKey(for: parsed))"
    }

    private static func bucketKey(for unit: ParsedUnit) -> String {
        if let family = unit.family {
            return "family:\(family.rawValue)"
        }
        return "unit:\(unit.code)"
    }
}

/// Vetoed evenings leave the shopping list. A skip keeps the recipe and its rows.
enum GroceryMealAudit {
    static func shops(isSkipped: Bool, isVetoed: Bool) -> Bool {
        // A skip keeps the recipe on the list. Only a veto removes it.
        if isSkipped { return !isVetoed }
        return !isVetoed
    }
}

/// Integer written to `shared_grocery_items.quantity` (migration 0008).
enum GrocerySyncQuantity {
    static func whole(_ quantity: Double?) -> Int {
        guard let quantity, quantity > 0 else { return 1 }
        return max(1, Int(quantity.rounded()))
    }
}
