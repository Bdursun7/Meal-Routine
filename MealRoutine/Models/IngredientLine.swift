import Foundation
import SwiftData

/// One ingredient row on a recipe. `ingredientId` is the UniTools merge key.
@Model
final class IngredientLine {
    var ingredientId: String
    var nameEN: String
    var nameTR: String
    var quantity: Double?
    var unit: String
    var scaling: String
    var note: String
    var trAliasCurated: Bool
    var sortIndex: Int
    var recipe: Recipe? = nil

    init(
        ingredientId: String,
        nameEN: String,
        nameTR: String,
        quantity: Double?,
        unit: String,
        scaling: String,
        note: String,
        trAliasCurated: Bool,
        sortIndex: Int
    ) {
        self.ingredientId = ingredientId
        self.nameEN = nameEN
        self.nameTR = nameTR
        self.quantity = quantity
        self.unit = unit
        self.scaling = scaling
        self.note = note
        self.trAliasCurated = trAliasCurated
        self.sortIndex = sortIndex
    }

    var displayName: String {
        if !nameTR.isEmpty { return nameTR }
        if !nameEN.isEmpty { return nameEN }
        return ingredientId
    }
}
