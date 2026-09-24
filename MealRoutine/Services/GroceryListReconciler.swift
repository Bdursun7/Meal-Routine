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

/// One ingredient the household marked on a recipe or a planned evening.
///
/// `coveredQuantity` and `unit` are the scaled amount at the moment of the check.
/// A later portion change that moves that amount no longer counts as covered.
struct IngredientCheckRecord: Codable, Equatable, Sendable {
    var mealUUID: UUID?
    var recipeSlug: String
    var ingredientId: String
    var sortIndex: Int
    var isChecked: Bool
    var coveredQuantity: Double?
    var unit: String
}

/// A scaled ingredient line that fed one evening on the shopping list.
struct GroceryContribution: Equatable, Sendable {
    var mealUUID: UUID
    var recipeSlug: String
    var sortIndex: Int
    var ingredientId: String
    var quantity: Double?
    var unit: String
}

/// How much of one merged grocery row is still needed.
struct GroceryCoverageOutcome: Equatable, Sendable {
    var remainingQuantity: Double?
    /// True only when covered quantity reaches the amount on the row.
    var isFullyChecked: Bool
    /// True when a stored check belongs to one of this row's contributions.
    var hasCoverage: Bool
    /// True when at least one contribution still matches the amount that was checked.
    var didCoverSome: Bool
}

/// Check flag written onto a grocery row after coverage is applied.
struct GroceryCheckResolution: Equatable, Sendable {
    var isChecked: Bool
    /// Set only for a partial cover, in the unit the row already displays.
    var uncoveredQuantity: Double?
}

/// Turns per-recipe ingredient checks into covered and remaining grocery amounts.
///
/// Soft-merged rows stay one line. Checking three tomatoes on one recipe and
/// leaving two unchecked on another leaves a remainder of two, not a checked
/// row of five. The row is fully checked only when covered quantity reaches
/// the amount the household sees, including a hand-edited quantity.
enum GroceryCoverage {
    static func stillCovers(
        isChecked: Bool,
        coveredQuantity: Double?,
        coveredUnit: String,
        quantity: Double?,
        unit: String
    ) -> Bool {
        guard isChecked else { return false }
        return GroceryCheckState.amountsMatch(
            previousQuantity: coveredQuantity,
            previousUnit: coveredUnit,
            nextQuantity: quantity,
            nextUnit: unit
        )
    }

    static func outcome(
        requiredQuantity: Double?,
        requiredUnit: String,
        contributions: [GroceryContribution],
        checks: [IngredientCheckRecord]
    ) -> GroceryCoverageOutcome {
        let scoped = contributions.filter { contribution in
            GroceryMerger.rowIdentity(ingredientId: contribution.ingredientId, unit: contribution.unit)
                == GroceryMerger.rowIdentity(ingredientId: contribution.ingredientId, unit: requiredUnit)
        }
        let relevant = checks.filter { check in
            scoped.contains { matches(check, $0) }
        }
        guard !relevant.isEmpty else {
            return GroceryCoverageOutcome(
                remainingQuantity: nil,
                isFullyChecked: false,
                hasCoverage: false,
                didCoverSome: false
            )
        }

        let covered = scoped.filter { contribution in
            relevant.contains { check in
                matches(check, contribution) && stillCovers(
                    isChecked: check.isChecked,
                    coveredQuantity: check.coveredQuantity,
                    coveredUnit: check.unit,
                    quantity: contribution.quantity,
                    unit: contribution.unit
                )
            }
        }
        let didCoverSome = !covered.isEmpty

        guard let requiredQuantity else {
            let allCovered = !scoped.isEmpty && scoped.allSatisfy { contribution in
                covered.contains { $0.mealUUID == contribution.mealUUID && $0.sortIndex == contribution.sortIndex }
            }
            return GroceryCoverageOutcome(
                remainingQuantity: nil,
                isFullyChecked: allCovered,
                hasCoverage: true,
                didCoverSome: didCoverSome
            )
        }

        let requiredBase = measuredBase(requiredQuantity, unit: requiredUnit) ?? 0
        let coveredBase = covered.reduce(0.0) { sum, contribution in
            sum + (measuredBase(contribution.quantity, unit: contribution.unit) ?? 0)
        }
        if coversRequired(covered: coveredBase, required: requiredBase) {
            return GroceryCoverageOutcome(
                remainingQuantity: nil,
                isFullyChecked: true,
                hasCoverage: true,
                didCoverSome: true
            )
        }
        let remainingBase = max(0, requiredBase - coveredBase)
        return GroceryCoverageOutcome(
            remainingQuantity: snap(quantity(fromBase: remainingBase, unit: requiredUnit)),
            isFullyChecked: false,
            hasCoverage: true,
            didCoverSome: didCoverSome
        )
    }

    /// Recipe coverage wins when any check exists for the row.
    /// Otherwise the previous grocery check stands, including a hand edit whose amount did not change.
    static func resolved(
        legacyKeepsCheck: Bool,
        outcome: GroceryCoverageOutcome
    ) -> GroceryCheckResolution {
        guard outcome.hasCoverage else {
            return GroceryCheckResolution(isChecked: legacyKeepsCheck, uncoveredQuantity: nil)
        }
        if outcome.isFullyChecked {
            return GroceryCheckResolution(isChecked: true, uncoveredQuantity: nil)
        }
        guard outcome.didCoverSome else {
            return GroceryCheckResolution(isChecked: false, uncoveredQuantity: nil)
        }
        return GroceryCheckResolution(isChecked: false, uncoveredQuantity: outcome.remainingQuantity)
    }

    private static func matches(_ check: IngredientCheckRecord, _ contribution: GroceryContribution) -> Bool {
        guard check.mealUUID == contribution.mealUUID,
              check.sortIndex == contribution.sortIndex,
              check.ingredientId == contribution.ingredientId else {
            return false
        }
        return GroceryMerger.rowIdentity(ingredientId: check.ingredientId, unit: check.unit)
            == GroceryMerger.rowIdentity(ingredientId: contribution.ingredientId, unit: contribution.unit)
    }

    private static func measuredBase(_ quantity: Double?, unit: String) -> Double? {
        guard let quantity else { return nil }
        return quantity * UnitNormalization.parse(unit).basePerUnit
    }

    private static func quantity(fromBase base: Double, unit: String) -> Double {
        let perUnit = UnitNormalization.parse(unit).basePerUnit
        guard perUnit != 0 else { return base }
        return base / perUnit
    }

    private static func coversRequired(covered: Double, required: Double) -> Bool {
        let scale = max(abs(covered), abs(required), 1)
        return covered + scale * 0.000_1 >= required
    }

    private static func snap(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}
