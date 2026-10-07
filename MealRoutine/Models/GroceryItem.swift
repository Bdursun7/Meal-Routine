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
    /// Set when the household edits the amount. Rebuild keeps this quantity and its unit.
    var quantityIsCustom: Bool = false
    /// Remaining need when only some of the merged amount is covered by recipe checks.
    /// Nil when the row is open with no partial cover, or when it is fully checked.
    var uncoveredQuantity: Double? = nil
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
        isManual: Bool = false,
        quantityIsCustom: Bool = false
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
        self.quantityIsCustom = quantityIsCustom
    }

    var displayName: String {
        if !nameTR.isEmpty { return nameTR }
        if !nameEN.isEmpty { return nameEN }
        return ingredientId
    }
}

/// A checked ingredient on one recipe, or on one planned evening when `mealUUID` is set.
/// Catalog-only checks (`mealUUID == nil`) stay on the recipe screen and do not change Market.
/// `coveredQuantity` is the scaled amount at the check. A later portion change stops covering.
@Model
final class IngredientCheck {
    var mealUUID: UUID?
    var recipeSlug: String
    var ingredientId: String
    var sortIndex: Int
    var isChecked: Bool
    var coveredQuantity: Double?
    var unit: String

    init(
        mealUUID: UUID?,
        recipeSlug: String,
        ingredientId: String,
        sortIndex: Int,
        isChecked: Bool,
        coveredQuantity: Double?,
        unit: String
    ) {
        self.mealUUID = mealUUID
        self.recipeSlug = recipeSlug
        self.ingredientId = ingredientId
        self.sortIndex = sortIndex
        self.isChecked = isChecked
        self.coveredQuantity = coveredQuantity
        self.unit = unit
    }
}

/// Household rows (`householdID` set) are a cache of the server. Personal rows (`householdID == nil`)
/// live only on this phone.
@Model
final class PantryItem {
    @Attribute(.unique) var uuid: UUID
    var householdID: UUID?
    var ingredientID: String
    var displayName: String
    var quantity: Double
    var unit: String
    var locationRaw: String
    var minimumQuantity: Double?
    /// The user's date (`dateValue`). The stored name predates the `dateType` split.
    var bestBefore: Date?
    /// `PantryDateType` raw value. Nil on rows saved before V5 had a type; those read as `bestBefore`.
    var dateTypeRaw: String?
    /// Server `version` this cache row was last confirmed at, plus local edits not yet confirmed.
    var revision: Int
    var updatedAt: Date

    init(
        uuid: UUID = UUID(),
        householdID: UUID?,
        ingredientID: String,
        displayName: String,
        quantity: Double,
        unit: String,
        location: PantryLocation = .pantry,
        minimumQuantity: Double? = nil,
        dateType: PantryDateType? = nil,
        dateValue: Date? = nil,
        revision: Int = 1,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid; self.householdID = householdID; self.ingredientID = ingredientID; self.displayName = displayName
        self.quantity = quantity; self.unit = unit; self.locationRaw = location.rawValue; self.minimumQuantity = minimumQuantity
        self.bestBefore = dateValue; self.dateTypeRaw = dateValue == nil ? nil : (dateType ?? .bestBefore).rawValue
        self.revision = revision; self.updatedAt = updatedAt
    }

    var location: PantryLocation { get { PantryLocation(rawValue: locationRaw) ?? .other } set { locationRaw = newValue.rawValue } }

    var dateValue: Date? { bestBefore }

    var dateType: PantryDateType? {
        guard bestBefore != nil else { return nil }
        return dateTypeRaw.flatMap(PantryDateType.init(rawValue:)) ?? .bestBefore
    }

    /// Both or neither: a date never exists without its type.
    func setDate(_ type: PantryDateType?, _ value: Date?) {
        if let type, let value {
            bestBefore = value
            dateTypeRaw = type.rawValue
        } else {
            bestBefore = nil
            dateTypeRaw = nil
        }
    }

    var isLowStock: Bool { minimumQuantity.map { quantity <= $0 } ?? false }

    var planningStock: PantryPlanningStock {
        PantryPlanningStock(ingredientId: ingredientID, quantity: quantity, unit: unit, dateType: dateType, dateValue: dateValue)
    }
}
