import Foundation

/// In-place grocery amount edits. The unit stays on the row; only the number changes.
enum GroceryQuantityEdit {
    /// Accepts `1,25` and `1.25`. Empty or non-numeric text does not write a row.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// A hand edit keeps its amount when the week is rebuilt. The editor does not change the unit.
    static func quantityToStore(planned: Double?, edited: Double?, isCustom: Bool) -> Double? {
        isCustom ? edited : planned
    }
}
