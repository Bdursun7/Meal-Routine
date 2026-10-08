import Foundation

/// Credits for bundled recipes. UniTools rows keep the CC BY-SA line.
/// MealRoutine originals must not be shown under that license.
enum Attribution {
    /// Do not reword. Required in About and the repository README, and on UniTools rows.
    static let uniTools = "Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)"

    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    static let landingURL = URL(string: "https://theunitools.com/en/data")!

    /// Prefix V3–V5.0 builds stored in `sourceAttribution` for personal recipes.
    private static let legacySourcePrefix = "Kaynak: "
    private static let legacyExternalName = "dış tarif"

    static func recipeLine(for recipe: Recipe) -> String {
        recipeLine(
            provider: recipe.sourceProvider,
            attribution: recipe.sourceAttribution,
            platform: recipe.sourcePlatform ?? .unknown,
            sourceTitle: recipe.sourceTitle,
            url: recipe.sourceURL
        )
    }

    /// Detail credit. UniTools rows keep `uniTools` verbatim. Any other provider
    /// shows its own attribution and never the CC BY-SA line.
    static func recipeLine(
        provider: String,
        attribution: String,
        platform: RecipeSourcePlatform = .unknown,
        sourceTitle: String = "",
        url: String = ""
    ) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "unitools" || key.isEmpty {
            return uniTools
        }
        let line = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        if key == "import" || key == "manual" || key == "saved" || key == "external" {
            if let name = RecipeSourceService.knownName(platform: platform, sourceTitle: sourceTitle, url: url) {
                return sourceLine(name)
            }
            let stored = line.hasPrefix(legacySourcePrefix) ? String(line.dropFirst(legacySourcePrefix.count)) : line
            if stored.isEmpty || stored == legacyExternalName {
                return L10n.text("recipe.attribution.external", "Kaynak: dış tarif")
            }
            return sourceLine(stored)
        }
        if line.isEmpty {
            return L10n.text("recipe.attribution.original", "Tarif: MealRoutine (özgün metin)")
        }
        return line
    }

    private static func sourceLine(_ name: String) -> String {
        L10n.format("recipe.attribution.source", "Kaynak: %@", name)
    }
}
