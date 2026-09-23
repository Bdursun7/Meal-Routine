import Foundation
import SwiftData

/// A merged shopping row for one week, or a manual extra.
@Model
final class GroceryItem {
    var uuid: UUID
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
    var hasUnitConflict: Bool
    var isChecked: Bool
    var isManual: Bool
    var week: PlanWeek? = nil

    init(
        uuid: UUID = UUID(),
        ingredientId: String,
        nameTR: String,
        nameEN: String,
        quantity: Double?,
        unit: String,
        hasUnitConflict: Bool,
        isChecked: Bool = false,
        isManual: Bool = false
    ) {
        self.uuid = uuid
        self.ingredientId = ingredientId
        self.nameTR = nameTR
        self.nameEN = nameEN
        self.quantity = quantity
        self.unit = unit
        self.hasUnitConflict = hasUnitConflict
        self.isChecked = isChecked
        self.isManual = isManual
    }

    var displayName: String {
        if !nameTR.isEmpty { return nameTR }
        if !nameEN.isEmpty { return nameEN }
        return ingredientId
    }
}
