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

enum PantryLocation: String, CaseIterable, Codable, Identifiable {
    case pantry, refrigerator, freezer, other
    var id: String { rawValue }
    var title: String {
        switch self { case .pantry: "Kiler"; case .refrigerator: "Buzdolabı"; case .freezer: "Dondurucu"; case .other: "Diğer" }
    }
}

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
    var bestBefore: Date?
    var revision: Int
    var updatedAt: Date

    init(uuid: UUID = UUID(), householdID: UUID?, ingredientID: String, displayName: String, quantity: Double, unit: String, location: PantryLocation = .pantry, minimumQuantity: Double? = nil, bestBefore: Date? = nil, revision: Int = 1, updatedAt: Date = .now) {
        self.uuid = uuid; self.householdID = householdID; self.ingredientID = ingredientID; self.displayName = displayName
        self.quantity = quantity; self.unit = unit; self.locationRaw = location.rawValue; self.minimumQuantity = minimumQuantity
        self.bestBefore = bestBefore; self.revision = revision; self.updatedAt = updatedAt
    }
    var location: PantryLocation { get { PantryLocation(rawValue: locationRaw) ?? .other } set { locationRaw = newValue.rawValue } }
    var isLowStock: Bool { minimumQuantity.map { quantity <= $0 } ?? false }
    var isExpiredOrNear: Bool { guard let bestBefore else { return false }; return bestBefore < Calendar.current.date(byAdding: .day, value: 2, to: .now)! }
}
