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

struct BundledCatalog: Sendable {
    var file: RecipeCatalogFile
    var fingerprint: String
}

enum RecipeCatalogLoader {
    static func load(bundle: Bundle = .main) throws -> RecipeCatalogFile {
        try loadBundled(bundle: bundle).file
    }

    static func load(from url: URL) throws -> RecipeCatalogFile {
        try loadBundled(from: url).file
    }

    static func loadBundled(bundle: Bundle = .main) throws -> BundledCatalog {
        guard let url = resourceURL(name: "recipes.v1", extension: "json", bundle: bundle) else {
            throw CatalogError.missingFile("recipes.v1.json")
        }
        return try loadBundled(from: url)
    }

    static func loadBundled(from url: URL) throws -> BundledCatalog {
        let name = url.lastPathComponent
        let data = try contents(of: url, name: name)
        let file = try decode(RecipeCatalogFile.self, from: data, name: name)
        return BundledCatalog(
            file: file,
            fingerprint: CatalogFingerprint.token(schemaVersion: file.schemaVersion, catalogFileBytes: data)
        )
    }

    static func loadAliases(bundle: Bundle = .main) -> [String: String] {
        guard let url = resourceURL(name: "ingredient-aliases.tr", extension: "json", bundle: bundle) else {
            return [:]
        }
        guard let data = try? contents(of: url, name: "ingredient-aliases.tr.json") else {
            return [:]
        }
        return (try? decode(IngredientAliasFile.self, from: data, name: "ingredient-aliases.tr.json").aliases) ?? [:]
    }

    private static func contents(of url: URL, name: String) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw CatalogError.unreadable(name)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, name: String) throws -> T {
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
        return bundle.urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first(where: { $0.lastPathComponent == expected })
    }
}
