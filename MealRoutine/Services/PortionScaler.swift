import Foundation

/// Scales a recipe quantity from `baseServings` to the active serving count.
///
/// The last argument is that active count: the household default, or one
/// evening's `PlannedMeal.servings` when that meal overrides it.
///
/// - linear: quantity × (active / base)
/// - damped: quantity × sqrt(active / base) for spices and similar
/// - fixed: unchanged (to-taste and other non-scaling rows)
enum PortionScaler {
    static func scale(
        quantity: Double?,
        scaling: String,
        baseServings: Int,
        householdSize: Int
    ) -> Double? {
        guard let quantity else { return nil }
        let base = max(baseServings, 1)
        let household = max(householdSize, 1)
        let ratio = Double(household) / Double(base)
        switch scaling {
        case "fixed":
            return quantity
        case "damped":
            return quantity * ratio.squareRoot()
        default:
            return quantity * ratio
        }
    }
}

/// Serving count the cook path and the grocery rebuild both use.
///
/// A positive `PlannedMeal.servings` is the per-evening override. Otherwise the
/// household default applies. Both are clamped to 1...8. Zero or negative meal
/// servings count as unset, so a bad stored row falls back to the household
/// instead of scaling quantities to nothing.
///
/// `PlannedMeal.servings` already exists on dogfood stores. Nothing new is
/// added to the schema; out-of-range values are clamped when read and rewritten
/// the next time someone taps Porsiyonu kaydet.
enum ActiveServings {
    static func resolve(mealServings: Int?, householdSize: Int) -> Int {
        let household = HouseholdSizeLimits.clamped(householdSize)
        guard let mealServings, mealServings > 0 else { return household }
        return HouseholdSizeLimits.clamped(mealServings)
    }
}
