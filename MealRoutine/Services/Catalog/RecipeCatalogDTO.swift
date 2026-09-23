import Foundation

struct RecipeCatalogFile: Decodable, Sendable {
    var schemaVersion: Int
    var app: String?
    var recipes: [RecipeDTO]
}

struct RecipeDTO: Decodable, Sendable {
    var id: String
    var source: SourceDTO
    var name: LocalizedText
    var nativeName: String?
    var summary: LocalizedText?
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
    var nutritionPerServing: NutritionDTO?
    var ingredients: [IngredientDTO]
    var steps: [StepDTO]
    var photo: PhotoDTO?
    var feedbackDefaults: FeedbackDefaultsDTO?
}

struct SourceDTO: Decodable, Sendable {
    var provider: String?
    var slug: String?
    var license: String?
    var attribution: String?
    var licenseUrl: String?
    var landingPage: String?
}

struct LocalizedText: Decodable, Sendable {
    var en: String?
    var tr: String?
}

struct NutritionDTO: Decodable, Sendable {
    var calories: Int?
    var protein: Int?
    var fat: Int?
    var carbs: Int?
}

struct IngredientDTO: Decodable, Sendable {
    var id: String
    var name: LocalizedText
    var quantity: Double?
    var unit: String
    var scaling: String
    var note: LocalizedText?
    var trAliasCurated: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, scaling, note, trAliasCurated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        scaling = try container.decodeIfPresent(String.self, forKey: .scaling) ?? "linear"
        note = try Self.decodeNote(from: container)
        trAliasCurated = try container.decodeIfPresent(Bool.self, forKey: .trAliasCurated) ?? false
        quantity = try FlexibleJSONNumber.decodeDoubleIfPresent(from: container, forKey: .quantity)
    }

    /// Notes ship as `{ en, tr }`. A plain string is still accepted as English-only.
    private static func decodeNote(from container: KeyedDecodingContainer<CodingKeys>) throws -> LocalizedText? {
        guard container.contains(.note) else { return nil }
        if try container.decodeNil(forKey: .note) { return nil }
        if let localized = try? container.decode(LocalizedText.self, forKey: .note) {
            let english = localized.en ?? ""
            let turkish = localized.tr ?? ""
            if english.isEmpty, turkish.isEmpty { return nil }
            return localized
        }
        if let plain = try? container.decode(String.self, forKey: .note) {
            if plain.isEmpty { return nil }
            return LocalizedText(en: plain, tr: nil)
        }
        return nil
    }
}

struct StepDTO: Decodable, Sendable {
    var text: LocalizedText
    var minutes: Int?
}

struct PhotoDTO: Decodable, Sendable {
    var url: String?
    var author: String?
    var license: String?
}

struct FeedbackDefaultsDTO: Decodable, Sendable {
    var loved: Int?
    var okay: Int?
    var never: Int?
}

struct IngredientAliasFile: Decodable, Sendable {
    var locale: String?
    var aliases: [String: String]
}

/// JSON numbers arrive as ints or doubles. `JSONDecoder` does not coerce between them.
enum FlexibleJSONNumber {
    static func decodeDoubleIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Double? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }
        return nil
    }
}
