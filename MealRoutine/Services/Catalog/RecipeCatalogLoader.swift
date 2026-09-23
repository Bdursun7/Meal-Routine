import Foundation

enum CatalogError: LocalizedError {
    case missingFile(String)
    case unsupportedSchema(Int)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name):
            "\(name) uygulama paketinde bulunamadı."
        case .unsupportedSchema(let version):
            "Tarif kataloğu şema sürümü desteklenmiyor (\(version))."
        case .unreadable(let name):
            "\(name) okunamadı."
        }
    }
}

enum RecipeCatalogLoader {
    static func load(bundle: Bundle = .main) throws -> RecipeCatalogFile {
        guard let url = resourceURL(name: "recipes.v1", extension: "json", bundle: bundle) else {
            throw CatalogError.missingFile("recipes.v1.json")
        }
        return try decode(RecipeCatalogFile.self, from: url, name: "recipes.v1.json")
    }

    static func load(from url: URL) throws -> RecipeCatalogFile {
        try decode(RecipeCatalogFile.self, from: url, name: url.lastPathComponent)
    }

    static func loadAliases(bundle: Bundle = .main) -> [String: String] {
        guard let url = resourceURL(name: "ingredient-aliases.tr", extension: "json", bundle: bundle) else {
            return [:]
        }
        return (try? decode(IngredientAliasFile.self, from: url, name: "ingredient-aliases.tr.json").aliases) ?? [:]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL, name: String) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CatalogError.unreadable(name)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CatalogError.unreadable(name)
        }
    }

    /// Synchronized Xcode groups often flatten resources into the bundle root.
    /// A folder reference keeps the `Recipes/` subdirectory. Try both.
    static func resourceURL(name: String, extension ext: String, bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Recipes") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        let expected = "\(name).\(ext)"
        return bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first {
            $0.lastPathComponent == expected
        }
    }
}
