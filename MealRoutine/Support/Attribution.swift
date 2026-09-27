import Foundation

/// Credits for bundled recipes. UniTools rows keep the CC BY-SA line.
/// MealRoutine originals must not be shown under that license.
enum Attribution {
    /// Do not reword. Required in About and the repository README, and on UniTools rows.
    static let uniTools = "Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)"

    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
    static let landingURL = URL(string: "https://theunitools.com/en/data")!

    /// Detail credit. UniTools rows keep `uniTools` verbatim. Any other provider
    /// shows its own attribution and never the CC BY-SA line.
    static func recipeLine(provider: String, attribution: String) -> String {
        let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "unitools" || key.isEmpty {
            return uniTools
        }
        let line = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            return "Tarif: MealRoutine (özgün metin)"
        }
        return line
    }
}
