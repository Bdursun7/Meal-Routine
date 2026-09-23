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
/// Quantities sum only when the unit matches. Mixed units stay on separate
/// rows and are flagged for a person to reconcile.
enum GroceryMerger {
    static func merge(_ lines: [GrocerySourceLine]) -> [MergedGroceryLine] {
        let grouped = Dictionary(grouping: lines, by: \.ingredientId)
        var merged: [MergedGroceryLine] = []
        merged.reserveCapacity(grouped.count)

        for (ingredientId, group) in grouped {
            let units = Set(group.map { normalize($0.unit) })
            let hasConflict = units.count > 1
            let byUnit = Dictionary(grouping: group) { normalize($0.unit) }

            for unit in byUnit.keys.sorted() {
                let unitLines = byUnit[unit] ?? []
                let quantities = unitLines.compactMap(\.quantity)
                let quantity: Double? = quantities.isEmpty ? nil : quantities.reduce(0, +)
                let nameTR = unitLines.first(where: { !$0.nameTR.isEmpty })?.nameTR
                    ?? unitLines.first?.nameEN
                    ?? ingredientId
                let nameEN = unitLines.first(where: { !$0.nameEN.isEmpty })?.nameEN ?? ""
                merged.append(
                    MergedGroceryLine(
                        ingredientId: ingredientId,
                        nameTR: nameTR,
                        nameEN: nameEN,
                        quantity: quantity,
                        unit: unit,
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

    static func normalize(_ unit: String) -> String {
        unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
