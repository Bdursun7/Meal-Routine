import Foundation
import SwiftData

/// Where a recipe came from. Catalog rows stay `builtIn`.
enum RecipeOrigin: String, Codable, CaseIterable, Sendable {
    case builtIn
    case manual
    case savedExternal
}

/// Personal collection. Built-in recipes stay `readyToCook`.
enum RecipeCollectionState: String, Codable, CaseIterable, Sendable {
    case savedToTry
    case readyToCook

    var title: String {
        switch self {
        case .savedToTry: "Denenecek"
        case .readyToCook: "Pişirmeye hazır"
        }
    }
}

/// Why a personal recipe cannot become ready to cook yet.
enum RecipeValidationIssue: String, Equatable, Sendable, Identifiable {
    case missingName
    case missingIngredient
    case missingQuantity
    case missingInstruction
    case emptyInstruction
    case missingServings

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingName: "Tarife bir ad ver"
        case .missingIngredient: "En az bir malzeme ekle"
        case .missingQuantity: "Her malzemenin bir miktarı olsun"
        case .missingInstruction: "En az bir yapılış adımı ekle"
        case .emptyInstruction: "Boş yapılış adımını sil veya yaz"
        case .missingServings: "Porsiyon 1 veya daha fazla olsun"
        }
    }
}

/// A field the recipe editor can focus when Kaydet fails.
enum RecipeEditorField: Hashable, Sendable {
    case name
    case servings
    case ingredientName(Int)
    case ingredientQuantity(Int)
    case step(Int)
}

/// Catalog unit codes. The editor stores these, not the Turkish label.
enum RecipeUnitChoices {
    static let codes = [
        "g", "kg", "ml", "l", "piece", "tbsp", "tsp", "clove", "toTaste", "sprig", "pinch", "slice",
    ]

    /// Known spellings fold to a catalog code. An empty unit stays empty. Anything else is kept.
    static func canonical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let code = UnitNormalization.parse(trimmed).code
        if codes.contains(code) { return code }
        return trimmed
    }
}

enum RecipeValidationResult: Equatable, Sendable {
    case valid
    case invalid([RecipeValidationIssue])

    var issues: [RecipeValidationIssue] {
        switch self {
        case .valid: []
        case .invalid(let issues): issues
        }
    }
}

/// One ingredient the cook typed. Nothing here is inferred from a web page.
struct RecipeFormIngredient: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: String
    var preparationNote: String
    var isOptional: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        quantity: Double? = nil,
        unit: String = "",
        preparationNote: String = "",
        isOptional: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationNote = preparationNote
        self.isOptional = isOptional
    }
}

/// Editor state shared by New Recipe, Complete Recipe, and Edit Recipe.
struct RecipeForm: Equatable, Sendable {
    var name: String
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var category: String
    var cuisine: String
    var difficulty: String
    var notes: String
    var ingredients: [RecipeFormIngredient]
    var steps: [String]
    var sourceURL: String
    var sourceTitle: String
    var sourcePlatform: RecipeSourcePlatform
    var sourceImagePath: String
    var origin: RecipeOrigin

    static func emptyManual() -> RecipeForm {
        RecipeForm(
            name: "",
            servings: nil,
            prepMinutes: nil,
            cookMinutes: nil,
            totalMinutes: nil,
            category: "",
            cuisine: "",
            difficulty: "",
            notes: "",
            ingredients: [RecipeFormIngredient()],
            steps: [""],
            sourceURL: "",
            sourceTitle: "",
            sourcePlatform: .unknown,
            sourceImagePath: "",
            origin: .manual
        )
    }
}

/// Kept so a dogfood store created during the old import spike still opens.
/// The collection uses `Recipe.collectionState` instead of this row.
@Model
final class RecipeImportDraft {
    var uuid: UUID
    var statusRaw: String
    var originRaw: String
    var sourceURL: String
    var title: String
    var payloadJSON: String
    var errorMessage: String
    var createdAt: Date
    var updatedAt: Date
    var linkedRecipeSlug: String

    init(
        uuid: UUID = UUID(),
        statusRaw: String = "",
        originRaw: String = "",
        sourceURL: String = "",
        title: String = "",
        payloadJSON: String = "",
        errorMessage: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        linkedRecipeSlug: String = ""
    ) {
        self.uuid = uuid
        self.statusRaw = statusRaw
        self.originRaw = originRaw
        self.sourceURL = sourceURL
        self.title = title
        self.payloadJSON = payloadJSON
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedRecipeSlug = linkedRecipeSlug
    }
}

