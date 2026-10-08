import Foundation

/// In-place grocery amount edits. The unit stays on the row; only the number changes.
enum GroceryQuantityEdit {
    /// Accepts `1,25` and `1.25` (see `QuantityFormat.parse`). Empty or non-numeric text does not write a row.
    static func parse(_ text: String, locale: Locale = RegionalContext.displayLocale) -> Double? {
        guard let value = QuantityFormat.parse(text, locale: locale), value >= 0 else { return nil }
        return value
    }

    /// A hand edit keeps its amount when the week is rebuilt. The editor does not change the unit.
    static func quantityToStore(planned: Double?, edited: Double?, isCustom: Bool) -> Double? {
        isCustom ? edited : planned
    }
}
