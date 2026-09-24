import Foundation

/// An automatic grocery row already stored for the week. Manual rows are not included.
struct AutoGroceryRow: Equatable, Sendable {
    var id: UUID
    var ingredientId: String
    var unit: String
    var quantity: Double?
    var isChecked: Bool
    /// Hand-edited amount. Rebuild keeps this quantity and only clears the check when it changes.
    var quantityIsCustom: Bool = false
}

struct GroceryReconcilePlan: Equatable, Sendable {
    struct Update: Equatable, Sendable {
        var existingID: UUID
        var mergedIndex: Int
        /// Check to store. False when the amount the household sees changed.
        var isChecked: Bool
    }

    var updates: [Update]
    var inserts: [Int]
    var deletes: [UUID]
}

/// Pairs a rebuilt shopping list with the automatic rows already on the week.
///
/// Matching uses `GroceryMerger.rowIdentity`, so gram and kilogram (millilitre
/// and litre) reuse one row. Each stored row is used at most once. When several
/// rows share an identity, a checked one is kept. That check is cleared when
/// the amount on the row changes.
enum GroceryListReconciler {
    static func plan(
        existingAuto: [AutoGroceryRow],
        merged: [MergedGroceryLine]
    ) -> GroceryReconcilePlan {
        var used: Set<UUID> = []
        var updates: [GroceryReconcilePlan.Update] = []
        var inserts: [Int] = []

        for (index, line) in merged.enumerated() {
            let identity = GroceryMerger.rowIdentity(ingredientId: line.ingredientId, unit: line.unit)
            let candidates = existingAuto.filter { row in
                !used.contains(row.id)
                    && GroceryMerger.rowIdentity(ingredientId: row.ingredientId, unit: row.unit) == identity
            }
            if let match = candidates.first(where: \.isChecked) ?? candidates.first {
                used.insert(match.id)
                updates.append(
                    GroceryReconcilePlan.Update(
                        existingID: match.id,
                        mergedIndex: index,
                        isChecked: GroceryCheckState.keepsCheckAfterRebuild(
                            wasChecked: match.isChecked,
                            storedQuantity: match.quantity,
                            storedUnit: match.unit,
                            plannedQuantity: line.quantity,
                            plannedUnit: line.unit,
                            quantityIsCustom: match.quantityIsCustom
                        )
                    )
                )
            } else {
                inserts.append(index)
            }
        }

        let deletes = existingAuto.map(\.id).filter { !used.contains($0) }
        return GroceryReconcilePlan(updates: updates, inserts: inserts, deletes: deletes)
    }
}

/// Whether a grocery check still applies after a rebuild or a hand edit.
///
/// The same physical amount stays checked, including grams that display as
/// kilograms. A different amount clears the check so the household notices.
/// A custom quantity compares the amount on screen, not the planned figure
/// hiding behind it.
enum GroceryCheckState {
    static func keepsCheckAfterRebuild(
        wasChecked: Bool,
        storedQuantity: Double?,
        storedUnit: String,
        plannedQuantity: Double?,
        plannedUnit: String,
        quantityIsCustom: Bool
    ) -> Bool {
        let nextQuantity = GroceryQuantityEdit.quantityToStore(
            planned: plannedQuantity,
            edited: storedQuantity,
            isCustom: quantityIsCustom
        )
        let nextUnit = quantityIsCustom ? storedUnit : plannedUnit
        return keepsCheck(
            wasChecked: wasChecked,
            previousQuantity: storedQuantity,
            previousUnit: storedUnit,
            nextQuantity: nextQuantity,
            nextUnit: nextUnit
        )
    }

    /// Check left after the household types a new amount on an existing row.
    static func checkedAfterQuantityEdit(
        wasChecked: Bool,
        previousQuantity: Double?,
        unit: String,
        editedQuantity: Double?
    ) -> Bool {
        keepsCheck(
            wasChecked: wasChecked,
            previousQuantity: previousQuantity,
            previousUnit: unit,
            nextQuantity: editedQuantity,
            nextUnit: unit
        )
    }

    static func keepsCheck(
        wasChecked: Bool,
        previousQuantity: Double?,
        previousUnit: String,
        nextQuantity: Double?,
        nextUnit: String
    ) -> Bool {
        guard wasChecked else { return false }
        return amountsMatch(
            previousQuantity: previousQuantity,
            previousUnit: previousUnit,
            nextQuantity: nextQuantity,
            nextUnit: nextUnit
        )
    }

    static func amountsMatch(
        previousQuantity: Double?,
        previousUnit: String,
        nextQuantity: Double?,
        nextUnit: String
    ) -> Bool {
        let previous = UnitNormalization.parse(previousUnit)
        let next = UnitNormalization.parse(nextUnit)
        switch (previousQuantity, nextQuantity) {
        case (nil, nil):
            return previous.code == next.code
        case (nil, _), (_, nil):
            return false
        case let (lhs?, rhs?):
            if let family = previous.family, family == next.family {
                return nearlyEqual(lhs * previous.basePerUnit, rhs * next.basePerUnit)
            }
            guard previous.code == next.code else { return false }
            return nearlyEqual(lhs, rhs)
        }
    }

    private static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        let scale = max(abs(lhs), abs(rhs), 1)
        return abs(lhs - rhs) <= scale * 0.000_1
    }
}
