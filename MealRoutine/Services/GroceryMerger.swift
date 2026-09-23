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
                        quantity: combined.quantity,
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

    /// Canonical unit code. Safe to store and to compare across rebuilds.
    static func normalize(_ unit: String) -> String {
        UnitNormalization.parse(unit).code
    }

    private static func bucketKey(for unit: ParsedUnit) -> String {
        if let family = unit.family {
            return "family:\(family.rawValue)"
        }
        return "unit:\(unit.code)"
    }
}
