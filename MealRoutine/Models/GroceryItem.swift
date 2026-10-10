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
    /// `0013` flag. Default false so a store saved before V5.1 still opens.
    var autoAddToGrocery: Bool = false
    /// Legacy V5.0 instant. The column stays `Date` so an existing store opens.
    /// A value here is not a calendar day and is never formatted into `dateValue`.
    var bestBefore: Date?
    /// Canonical pantry day, `YYYY-MM-DD`. Nil when the user entered no date.
    /// Added as an optional column so stores saved before V5.1 still open.
    var calendarDay: String? = nil
    /// `PantryDateType` raw value. Nil when `calendarDay` is nil.
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
        autoAddToGrocery: Bool = false,
        dateType: PantryDateType? = nil,
        dateValue: String? = nil,
        revision: Int = 1,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid; self.householdID = householdID; self.ingredientID = ingredientID; self.displayName = displayName
        self.quantity = quantity; self.unit = unit; self.locationRaw = location.rawValue; self.minimumQuantity = minimumQuantity
        self.autoAddToGrocery = autoAddToGrocery
        let day = PantryDay.canonical(dateValue)
        self.calendarDay = day
        self.bestBefore = nil
        self.dateTypeRaw = day == nil ? nil : (dateType ?? .bestBefore).rawValue
        self.revision = revision; self.updatedAt = updatedAt
    }

    var location: PantryLocation { get { PantryLocation(rawValue: locationRaw) ?? .other } set { locationRaw = newValue.rawValue } }

    var dateValue: String? { calendarDay }

    /// True when this row still holds a V5.0 instant and no calendar day.
    var hasLegacyDateInstant: Bool { bestBefore != nil && calendarDay == nil }

    var dateType: PantryDateType? {
        guard calendarDay != nil else { return nil }
        return dateTypeRaw.flatMap(PantryDateType.init(rawValue:)) ?? .bestBefore
    }

    var dateAuthority: PantryDateAuthority {
        if let day = calendarDay, let type = dateType {
            return .day(type, day)
        }
        if hasLegacyDateInstant { return .legacyInstant }
        return .none
    }

    /// Both or neither. A stored day is `YYYY-MM-DD`. The legacy instant is cleared.
    func setDate(_ type: PantryDateType?, _ day: String?) {
        if let type, let day = PantryDay.canonical(day) {
            calendarDay = day
            dateTypeRaw = type.rawValue
            bestBefore = nil
        } else {
            calendarDay = nil
            dateTypeRaw = nil
            bestBefore = nil
        }
    }

    /// Copies the server day and drops any legacy instant. Does not read `bestBefore`.
    func applyServerDate(type: PantryDateType?, day: String?) {
        setDate(type, PantryHouseholdDate.canonicalDay(serverDateValue: day))
    }

    var isLowStock: Bool { minimumQuantity.map { quantity <= $0 } ?? false }

    var planningStock: PantryPlanningStock {
        PantryPlanningStock(ingredientId: ingredientID, quantity: quantity, unit: unit, dateType: dateType, dateValue: dateValue)
    }
}
