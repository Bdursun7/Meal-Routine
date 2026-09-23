import Foundation
import SwiftData

/// A dinner from the bundled UniTools catalog.
@Model
final class Recipe {
    @Attribute(.unique) var slug: String
    var nameEN: String
    var nameTR: String
    var nativeName: String
    var summaryEN: String
    var summaryTR: String
    var country: String
    var category: String
    var unitoolsCategory: String
    var diets: [String]
    var difficulty: String
    var baseServings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var totalMinutes: Int
    var tags: [String]
    var trDogfoodScore: Int
    var hardIngredientPenalty: Int
    var calories: Int
    var protein: Int
    var fat: Int
    var carbs: Int
    var sourceProvider: String
    var sourceLicense: String
    var sourceAttribution: String
    var photoURL: String
    var photoAuthor: String
    var photoLicense: String

    @Relationship(deleteRule: .cascade, inverse: \IngredientLine.recipe)
    var ingredients: [IngredientLine] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep] = []

    init(
        slug: String,
        nameEN: String,
        nameTR: String,
        nativeName: String,
        summaryEN: String,
        summaryTR: String,
        country: String,
        category: String,
        unitoolsCategory: String,
        diets: [String],
        difficulty: String,
        baseServings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        totalMinutes: Int,
        tags: [String],
        trDogfoodScore: Int,
        hardIngredientPenalty: Int,
        calories: Int,
        protein: Int,
        fat: Int,
        carbs: Int,
        sourceProvider: String,
        sourceLicense: String,
        sourceAttribution: String,
        photoURL: String,
        photoAuthor: String,
        photoLicense: String
    ) {
        self.slug = slug
        self.nameEN = nameEN
        self.nameTR = nameTR
        self.nativeName = nativeName
        self.summaryEN = summaryEN
        self.summaryTR = summaryTR
        self.country = country
        self.category = category
        self.unitoolsCategory = unitoolsCategory
        self.diets = diets
        self.difficulty = difficulty
        self.baseServings = baseServings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.totalMinutes = totalMinutes
        self.tags = tags
        self.trDogfoodScore = trDogfoodScore
        self.hardIngredientPenalty = hardIngredientPenalty
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.sourceProvider = sourceProvider
        self.sourceLicense = sourceLicense
        self.sourceAttribution = sourceAttribution
        self.photoURL = photoURL
        self.photoAuthor = photoAuthor
        self.photoLicense = photoLicense
    }

    var displayName: String {
        if !nameTR.isEmpty { return nameTR }
        if !nameEN.isEmpty { return nameEN }
        return nativeName
    }

    var ingredientIDs: Set<String> {
        Set(ingredients.map(\.ingredientId))
    }
}
