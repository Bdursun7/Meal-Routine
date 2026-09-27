import Foundation
import SwiftData

/// Where a recipe came from. Catalog rows stay `builtIn`.
enum RecipeOrigin: String, Codable, CaseIterable, Sendable {
    case builtIn
    case imported
    case manual
}

/// Lifecycle of one import. Drafts use the same cases and never enter planning.
enum RecipeImportStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case extracting
    case needsReview
    case ready
    case failed
    case cancelled
}

/// Drafts the cook can resume. `ready` on a draft means it can be saved, not that it is in the catalog.
enum RecipeDraftState: String, Codable, CaseIterable, Sendable {
    case started
    case extracting
    case needsReview
    case incomplete
    case ready
    case cancelled
    case failed
}

/// Public source the cook shared or pasted. Not a claim that MealRoutine wrote the recipe.
enum RecipeSourcePlatform: String, Codable, CaseIterable, Sendable {
    case website
    case instagram
    case tiktok
    case youtube
    case safari
    case notes
    case messages
    case unknown

    var title: String {
        switch self {
        case .website: "Web sitesi"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .safari: "Safari"
        case .notes: "Notlar"
        case .messages: "Mesajlar"
        case .unknown: "Bilinmeyen kaynak"
        }
    }

    var isSocialPost: Bool {
        switch self {
        case .instagram, .tiktok, .youtube: true
        case .website, .safari, .notes, .messages, .unknown: false
        }
    }
}

/// One ingredient line before it is stored on `IngredientLine`.
struct ImportedIngredient: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var preparationNote: String?
    var isOptional: Bool
    var isUncertain: Bool
    var originalText: String
    var sortOrder: Int
    /// False when the line could not be structured. Grocery waits for an explicit enable.
    var includeInGrocery: Bool

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: String? = nil,
        preparationNote: String? = nil,
        isOptional: Bool = false,
        isUncertain: Bool = false,
        originalText: String = "",
        sortOrder: Int = 0,
        includeInGrocery: Bool = true
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationNote = preparationNote
        self.isOptional = isOptional
        self.isUncertain = isUncertain
        self.originalText = originalText
        self.sortOrder = sortOrder
        self.includeInGrocery = includeInGrocery
    }
}

/// One ordered step before it is stored on `RecipeStep`.
struct ImportedInstruction: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var sortOrder: Int
    var isUncertain: Bool
    var originalText: String

    init(
        id: UUID = UUID(),
        text: String,
        sortOrder: Int = 0,
        isUncertain: Bool = false,
        originalText: String = ""
    ) {
        self.id = id
        self.text = text
        self.sortOrder = sortOrder
        self.isUncertain = isUncertain
        self.originalText = originalText
    }
}

enum ImportWarning: String, Codable, CaseIterable, Sendable {
    case missingTime
    case uncertainQuantities
    case missingInstructions
    case missingIngredients
    case missingTitle
    case incompleteSource
    case socialWithoutRecipe

    var message: String {
        switch self {
        case .missingTime:
            "Süre yok. Planlayıcı, bir süre yazılana kadar bu tarifi kendiliğinden seçmez."
        case .uncertainQuantities:
            "Bazı miktarlar belirsiz. Eksik miktar uydurulmadı."
        case .missingInstructions:
            "Yapılış eksik. Kaydetmek için adımları yaz veya eksik olduğunu onayla."
        case .missingIngredients:
            "Malzeme eksik. Kaydetmek için malzeme yaz veya eksik olduğunu onayla."
        case .missingTitle:
            "Tarifin bir adı olmalı."
        case .incompleteSource:
            "Kaynak eksik. Metni yapıştırabilir veya tarifi elle girebilirsin."
        case .socialWithoutRecipe:
            "Bu paylaşımda tam tarif yok. Metni yapıştır veya tarifi elle gir."
        }
    }
}

/// Editable import before it becomes a `Recipe`. Nothing here is trusted until the cook saves it.
struct RecipeImportDocument: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var category: String
    var cuisine: String
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var servings: Int?
    var difficulty: String
    var ingredients: [ImportedIngredient]
    var instructions: [ImportedInstruction]
    var sourceURL: String
    var sourceTitle: String
    var sourcePlatform: RecipeSourcePlatform
    var sourceKey: String
    var extractionConfidence: Double?
    var origin: RecipeOrigin
    var isUserEdited: Bool
    var notes: String
    var confirmedMissingIngredients: Bool
    var confirmedMissingInstructions: Bool

    static func emptyManual() -> RecipeImportDocument {
        RecipeImportDocument(
            title: "",
            summary: "",
            category: "",
            cuisine: "",
            prepMinutes: nil,
            cookMinutes: nil,
            totalMinutes: nil,
            servings: nil,
            difficulty: "unknown",
            ingredients: [
                ImportedIngredient(name: "", originalText: "", sortOrder: 0, includeInGrocery: false)
            ],
            instructions: [
                ImportedInstruction(text: "", sortOrder: 0)
            ],
            sourceURL: "",
            sourceTitle: "",
            sourcePlatform: .unknown,
            sourceKey: "",
            extractionConfidence: nil,
            origin: .manual,
            isUserEdited: false,
            notes: "",
            confirmedMissingIngredients: false,
            confirmedMissingInstructions: false
        )
    }

    var timeIsUnknown: Bool {
        totalMinutes == nil && prepMinutes == nil && cookMinutes == nil
    }

    var warnings: [ImportWarning] {
        var items: [ImportWarning] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(.missingTitle)
        }
        if timeIsUnknown {
            items.append(.missingTime)
        }
        let namedIngredients = ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if namedIngredients.isEmpty {
            items.append(.missingIngredients)
        } else if namedIngredients.contains(where: \.isUncertain) {
            items.append(.uncertainQuantities)
        }
        let steps = instructions.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if steps.isEmpty {
            items.append(.missingInstructions)
        }
        if origin == .imported, sourceURL.isEmpty, sourceTitle.isEmpty {
            items.append(.incompleteSource)
        }
        if sourcePlatform.isSocialPost && namedIngredients.isEmpty && steps.isEmpty {
            items.append(.socialWithoutRecipe)
        }
        return items
    }

    /// Copies only the fields the cook chose. Unselected fields stay on `self`.
    func applying(_ incoming: RecipeImportDocument, fields: Set<ReimportField>) -> RecipeImportDocument {
        var copy = self
        if fields.contains(.title) { copy.title = incoming.title }
        if fields.contains(.summary) { copy.summary = incoming.summary }
        if fields.contains(.category) { copy.category = incoming.category }
        if fields.contains(.cuisine) { copy.cuisine = incoming.cuisine }
        if fields.contains(.time) {
            copy.prepMinutes = incoming.prepMinutes
            copy.cookMinutes = incoming.cookMinutes
            copy.totalMinutes = incoming.totalMinutes
        }
        if fields.contains(.servings) { copy.servings = incoming.servings }
        if fields.contains(.difficulty) { copy.difficulty = incoming.difficulty }
        if fields.contains(.ingredients) { copy.ingredients = incoming.ingredients }
        if fields.contains(.instructions) { copy.instructions = incoming.instructions }
        if fields.contains(.source) {
            copy.sourceURL = incoming.sourceURL
            copy.sourceTitle = incoming.sourceTitle
            copy.sourcePlatform = incoming.sourcePlatform
            copy.sourceKey = incoming.sourceKey
        }
        if fields.contains(.notes) { copy.notes = incoming.notes }
        copy.extractionConfidence = incoming.extractionConfidence
        return copy
    }
}

/// Fields a re-import may replace. Omitted fields keep the cook's current text.
enum ReimportField: String, Codable, CaseIterable, Sendable, Identifiable {
    case title
    case summary
    case category
    case cuisine
    case time
    case servings
    case difficulty
    case ingredients
    case instructions
    case source
    case notes

    var id: String { rawValue }

    var titleText: String {
        switch self {
        case .title: "Ad"
        case .summary: "Açıklama"
        case .category: "Kategori"
        case .cuisine: "Mutfak"
        case .time: "Süre"
        case .servings: "Porsiyon"
        case .difficulty: "Zorluk"
        case .ingredients: "Malzemeler"
        case .instructions: "Yapılış"
        case .source: "Kaynak"
        case .notes: "Notlar"
        }
    }
}

struct ReimportFieldChange: Equatable, Sendable, Identifiable {
    var field: ReimportField
    var currentText: String
    var incomingText: String

    var id: String { field.rawValue }
}

/// A saved import that is not yet a recipe. Planning, grocery, and recommendations ignore these rows.
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
    /// Saved recipe this draft is updating. Empty for a new import.
    var linkedRecipeSlug: String

    init(
        uuid: UUID = UUID(),
        status: RecipeDraftState,
        origin: RecipeOrigin,
        sourceURL: String = "",
        title: String = "",
        payloadJSON: String = "",
        errorMessage: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        linkedRecipeSlug: String = ""
    ) {
        self.uuid = uuid
        self.statusRaw = status.rawValue
        self.originRaw = origin.rawValue
        self.sourceURL = sourceURL
        self.title = title
        self.payloadJSON = payloadJSON
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedRecipeSlug = linkedRecipeSlug
    }

    var state: RecipeDraftState {
        get { RecipeDraftState(rawValue: statusRaw) ?? .started }
        set { statusRaw = newValue.rawValue }
    }

    var origin: RecipeOrigin {
        get { RecipeOrigin(rawValue: originRaw) ?? .imported }
        set { originRaw = newValue.rawValue }
    }
}

/// Plain identity used by duplicate checks. Built from `Recipe` or a fixture.
struct RecipeDuplicateInput: Equatable, Sendable {
    var slug: String
    var title: String
    var sourceURL: String
    var sourceKey: String
    var ingredientNames: [String]
    var isUserEdited: Bool
    var origin: RecipeOrigin
}

enum DuplicateStrength: String, Equatable, Sendable {
    case strong
    case medium
}

struct DuplicateCandidate: Equatable, Sendable, Identifiable {
    var slug: String
    var title: String
    var strength: DuplicateStrength
    var reason: String
    var isUserEdited: Bool

    var id: String { slug }
}
