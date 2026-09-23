import Foundation

/// Scales a recipe quantity when household size differs from `baseServings`.
///
/// - linear: quantity × (household / base)
/// - damped: quantity × sqrt(household / base) for spices and similar
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
