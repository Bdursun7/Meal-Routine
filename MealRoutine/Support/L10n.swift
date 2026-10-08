import Foundation

/// Lookup for keyed UI text in `Localizable.xcstrings`. The Turkish source text is passed with the
/// key, so a missing translation still renders the development-language copy. Business logic
/// returns ids and enums; only presentation code calls this.
enum L10n {
    static var bundle: Bundle = .main

    static func text(_ key: String, _ source: String) -> String {
        bundle.localizedString(forKey: key, value: source, table: nil)
    }

    /// `source` uses `%@` / `%d` / `%lld` placeholders in the catalog's format.
    static func format(_ key: String, _ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(key, source), locale: RegionalContext.displayLocale, arguments: arguments)
    }
}
