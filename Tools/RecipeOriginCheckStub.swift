/// Foundation-only stand-in for the photo check script.
///
/// `CatalogIntegrity.swift` asks whether a row is bundled. The real `RecipeOrigin`
/// lives in `RecipeImportModels.swift`, which imports SwiftData, so this script
/// cannot compile that file. The cases match the app enum.
enum RecipeOrigin: String {
    case builtIn
    case manual
    case savedExternal
}
