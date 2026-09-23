import Foundation

/// An automatic grocery row already stored for the week. Manual rows are not included.
struct AutoGroceryRow: Equatable, Sendable {
    var id: UUID
    var ingredientId: String
    var unit: String
    var isChecked: Bool
}

struct GroceryReconcilePlan: Equatable, Sendable {
    struct Update: Equatable, Sendable {
        var existingID: UUID
        var mergedIndex: Int
        /// Check state to leave on the row. Rebuild must not clear this.
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
/// rows share an identity, a checked one is kept.
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
                        isChecked: match.isChecked
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
