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

/// Caps for text the cook types. The editor clamps at these lengths; save rejects anything longer.
enum RecipeFieldLimits {
    static let name = 80
    static let ingredientName = 60
    static let preparationNote = 80
    static let step = 500
    static let notes = 1000
    static let sourceURL = 500
    static let sourceTitle = 120
    static let category = 40
    static let cuisine = 40
    static let servingsDigits = 3
    static let minutesDigits = 4
    static let quantityIntegerDigits = 6
    static let quantityFractionDigits = 2

    /// Longest quantity the field keeps: digits, one separator, and a short fraction.
    static var quantityCharacters: Int {
        quantityIntegerDigits + 1 + quantityFractionDigits
    }
}

/// Cuts pasted text at the field cap so a long paste cannot fill the form.
enum RecipeTextLimit {
    static func clamp(_ raw: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, raw.count > maxCharacters else { return raw }
        return String(raw.prefix(maxCharacters))
    }
}

/// Whole numbers (servings, minutes) and one decimal (quantity). Empty is not an error by itself.
enum RecipeNumericInput {
    enum Whole: Equatable {
        case empty
        case value(Int)
        case notANumber
        case tooManyDigits
    }

    enum DecimalValue: Equatable {
        case empty
        case value(Double)
        case notANumber
        case tooLong
    }

    static func whole(_ raw: String, maxDigits: Int) -> Whole {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        guard trimmed.allSatisfy(isASCIIDigit) else { return .notANumber }
        if trimmed.count > maxDigits { return .tooManyDigits }
        guard let number = Int(trimmed) else { return .notANumber }
        return .value(number)
    }

    static func decimal(_ raw: String) -> DecimalValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        var separatorCount = 0
        var integerDigits = 0
        var fractionDigits = 0
        var seenSeparator = false
        for character in trimmed {
            if isASCIIDigit(character) {
                if seenSeparator {
                    fractionDigits += 1
                } else {
                    integerDigits += 1
                }
            } else if character == "." || character == "," {
                separatorCount += 1
                seenSeparator = true
            } else {
                return .notANumber
            }
        }
        if separatorCount > 1 || (integerDigits == 0 && fractionDigits == 0) {
            return .notANumber
        }
        if integerDigits > RecipeFieldLimits.quantityIntegerDigits
            || fractionDigits > RecipeFieldLimits.quantityFractionDigits {
            return .tooLong
        }
        guard let number = QuantityFormat.parse(trimmed) else { return .notANumber }
        return .value(number)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }
}

/// Why a personal recipe cannot become ready to cook yet.
enum RecipeValidationIssue: String, Equatable, Sendable, Identifiable {
    case missingName
    case missingIngredient
    case missingQuantity
    case missingUnit
    case missingInstruction
    case emptyInstruction
    case missingServings
    case invalidServings
    case invalidQuantity
    case invalidMinutes
    case nameTooLong
    case ingredientNameTooLong
    case preparationNoteTooLong
    case stepTooLong
    case notesTooLong
    case sourceURLTooLong
    case sourceTitleTooLong
    case categoryTooLong
    case cuisineTooLong
    case servingsTooLong
    case minutesTooLong
    case quantityTooLong

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingName: "Tarife bir ad ver"
        case .missingIngredient: "En az bir malzeme ekle"
        case .missingQuantity: "Her malzemenin bir miktarı olsun"
        case .missingUnit: "Her malzemenin bir birimi olsun"
        case .missingInstruction: "En az bir yapılış adımı ekle"
        case .emptyInstruction: "Boş yapılış adımını sil veya yaz"
        case .missingServings: "Porsiyon 1 veya daha fazla olsun"
        case .invalidServings: "Porsiyon bir sayı olsun"
        case .invalidQuantity: "Miktar bir sayı olsun"
        case .invalidMinutes: "Süre bir sayı olsun"
        case .nameTooLong: "Ad en fazla \(RecipeFieldLimits.name) karakter olsun"
        case .ingredientNameTooLong: "Malzeme adı en fazla \(RecipeFieldLimits.ingredientName) karakter olsun"
        case .preparationNoteTooLong: "Hazırlık notu en fazla \(RecipeFieldLimits.preparationNote) karakter olsun"
        case .stepTooLong: "Adım en fazla \(RecipeFieldLimits.step) karakter olsun"
        case .notesTooLong: "Not en fazla \(RecipeFieldLimits.notes) karakter olsun"
        case .sourceURLTooLong: "Kaynak adresi en fazla \(RecipeFieldLimits.sourceURL) karakter olsun"
        case .sourceTitleTooLong: "Kaynak başlığı en fazla \(RecipeFieldLimits.sourceTitle) karakter olsun"
        case .categoryTooLong: "Kategori en fazla \(RecipeFieldLimits.category) karakter olsun"
        case .cuisineTooLong: "Mutfak en fazla \(RecipeFieldLimits.cuisine) karakter olsun"
        case .servingsTooLong: "Porsiyon en fazla \(RecipeFieldLimits.servingsDigits) rakam olsun"
        case .minutesTooLong: "Süre en fazla \(RecipeFieldLimits.minutesDigits) rakam olsun"
        case .quantityTooLong: "Miktar en fazla \(RecipeFieldLimits.quantityIntegerDigits) basamak olsun"
        }
    }
}

/// A field the recipe editor can focus when Kaydet fails.
enum RecipeEditorField: Hashable, Sendable {
    case name
    case servings
    case ingredientName(Int)
    case ingredientQuantity(Int)
    case ingredientUnit(Int)
    case ingredientNote(Int)
    case step(Int)
    case prepMinutes
    case cookMinutes
    case totalMinutes
    case category
    case cuisine
    case notes
    case sourceURL
    case sourceTitle
}

/// Structured unit codes (`UnitCode`). The editor stores these, never a display label.
enum RecipeUnitChoices {
    static let codes: [String] = {
        let units: [UnitCode] = [
            .g, .kg, .ml, .l, .piece, .tbsp, .tsp, .clove, .toTaste, .sprig, .pinch, .slice,
            .cup, .package, .can, .bottle, .oz, .lb,
        ]
        return units.map { $0.rawValue }
    }()

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
    /// What the cook typed in Miktar. Empty means `quantity` is the source of truth.
    var quantityText: String
    var unit: String
    var preparationNote: String
    var isOptional: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        quantity: Double? = nil,
        quantityText: String = "",
        unit: String = "",
        preparationNote: String = "",
        isOptional: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.quantityText = quantityText
        self.unit = unit
        self.preparationNote = preparationNote
        self.isOptional = isOptional
    }
}

/// Editor state shared by New Recipe, Complete Recipe, and Edit Recipe.
struct RecipeForm: Equatable, Sendable {
    var name: String
    var servings: Int?
    /// What the cook typed in Porsiyon. Empty means `servings` is the source of truth.
    var servingsText: String = ""
    var prepMinutes: Int?
    var prepMinutesText: String = ""
    var cookMinutes: Int?
    var cookMinutesText: String = ""
    var totalMinutes: Int?
    var totalMinutesText: String = ""
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
            servingsText: "",
            prepMinutes: nil,
            prepMinutesText: "",
            cookMinutes: nil,
            cookMinutesText: "",
            totalMinutes: nil,
            totalMinutesText: "",
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

