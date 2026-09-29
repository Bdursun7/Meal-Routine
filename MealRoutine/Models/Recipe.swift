import Foundation
import SwiftData

/// A dinner from the bundled catalog. UniTools rows and MealRoutine originals share this model.
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
    /// Catalog `photo` fields. Empty strings mean there is no photo. Seed copies the
    /// JSON url, author, and license as shipped; the UI does not invent a credit.
    var photoURL: String
    var photoAuthor: String
    var photoLicense: String

    /// V3 import metadata. Existing catalog rows migrate as built-in.
    /// Defaults keep the lightweight SwiftData migration compatible with V1/V2 stores.
    var originRaw: String = RecipeOrigin.builtIn.rawValue
    var sourceURL: String = ""
    var sourceTitle: String = ""
    var sourcePlatformRaw: String = ""
    /// Stable id such as an Instagram shortcode. Empty when the source has none.
    var sourceKey: String = ""
    var importedAt: Date? = nil
    var lastImportedAt: Date? = nil
    var importStatusRaw: String = ""
    var extractionConfidence: Double? = nil
    var requiresReview: Bool = false
    var isUserEdited: Bool = false
    var userNotes: String = ""
    /// True when the cook confirmed a recipe that still has no ingredient lines.
    var confirmedMissingIngredients: Bool = false
    /// True when the cook confirmed a recipe that still has no instruction steps.
    var confirmedMissingInstructions: Bool = false
    /// True when total time was not in the source and the cook has not set one.
    /// Unknown time is not stored as zero minutes of cooking.
    var timeIsUnknown: Bool = false
    /// True when the source did not give a yield. Amounts stay as written.
    var servingsUnspecified: Bool = false

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

    /// V1 shows the Turkish summary. English remains in the catalog for attribution.
    var displaySummary: String {
        if !summaryTR.isEmpty { return summaryTR }
        return summaryEN
    }

    var ingredientIDs: Set<String> {
        Set(ingredients.map(\.ingredientId))
    }

    var origin: RecipeOrigin {
        get { RecipeOrigin(rawValue: originRaw) ?? .builtIn }
        set { originRaw = newValue.rawValue }
    }

    var sourcePlatform: RecipeSourcePlatform? {
        get {
            let raw = sourcePlatformRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return RecipeSourcePlatform(rawValue: raw)
        }
        set { sourcePlatformRaw = newValue?.rawValue ?? "" }
    }

    var importStatus: RecipeImportStatus? {
        get {
            let raw = importStatusRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return RecipeImportStatus(rawValue: raw)
        }
        set { importStatusRaw = newValue?.rawValue ?? "" }
    }

    /// Bundled UniTools and MealRoutine originals. User imports are never this.
    var isBundledCatalog: Bool {
        origin == .builtIn
    }
}
