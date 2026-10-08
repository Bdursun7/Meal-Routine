import Foundation

/// One row of the central ingredient dictionary (`Recipes/ingredients.v2.json`).
/// The server seeds the same rows (`0012`, locale tables in `0013`); the server copy is authoritative.
/// `id` is the identity. `names` and `aliases` are display data keyed by locale (`"tr-TR"`).
struct IngredientEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Locale the dictionary was authored in. V3 `import:` ids were minted from these names.
    static let sourceLocale = "tr-TR"

    var id: String
    var names: [String: String]
    var aliases: [String: [String]]
    var sourceIds: [String]

    init(id: String, names: [String: String], aliases: [String: [String]] = [:], sourceIds: [String] = []) {
        self.id = id
        self.names = names
        self.aliases = aliases
        self.sourceIds = sourceIds
    }

    /// A row whose name was typed or shown in `locale`.
    init(id: String, name: String, synonyms: [String] = [], sourceIds: [String] = [], locale: String = RegionalContext.contentLocale) {
        self.init(id: id, names: [locale: name], aliases: synonyms.isEmpty ? [:] : [locale: synonyms], sourceIds: sourceIds)
    }

    /// Name in `locale`, else the source-locale name.
    func name(in locale: String) -> String {
        names[locale] ?? names[Self.sourceLocale] ?? names.keys.sorted().first.flatMap { names[$0] } ?? id
    }

    /// Aliases in `locale`. Source-locale aliases apply only when the row has no name in `locale`.
    func aliases(in locale: String) -> [String] {
        if let list = aliases[locale] { return list }
        return names[locale] == nil ? aliases[Self.sourceLocale] ?? [] : []
    }

    var name: String { name(in: RegionalContext.contentLocale) }
    var synonyms: [String] { aliases(in: RegionalContext.contentLocale) }

    private enum CodingKeys: String, CodingKey {
        case id, names, aliases, sourceIds
        case name, displayName, synonyms
    }

    /// Reads v2 rows (`names`/`aliases`) and pre-V5.1 rows (`name` or `displayName`, `synonyms`),
    /// which were always source-locale text.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceIds = try container.decodeIfPresent([String].self, forKey: .sourceIds) ?? []
        let legacyName = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
        let legacySynonyms = try container.decodeIfPresent([String].self, forKey: .synonyms) ?? []
        if let decoded = try container.decodeIfPresent([String: String].self, forKey: .names), !decoded.isEmpty {
            names = decoded
            aliases = try container.decodeIfPresent([String: [String]].self, forKey: .aliases) ?? [:]
        } else {
            names = [Self.sourceLocale: legacyName ?? id]
            aliases = legacySynonyms.isEmpty ? [:] : [Self.sourceLocale: legacySynonyms]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(names, forKey: .names)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(sourceIds, forKey: .sourceIds)
    }
}

/// Recipe, grocery and pantry lines meet on `ingredientId`. Display names never decide identity.
/// A catalog id resolves through `sourceIds`; a V3 `import:<folded name>` id resolves only when that
/// name is an unambiguous source-locale (tr-TR) dictionary name or alias, so the active locale never
/// changes which ingredient an id means. `custom:<uuid>` ids are user-created and
/// match only themselves. Everything else, including `manual:` grocery rows, matches nothing.
struct IngredientDictionary: Sendable {
    static let customPrefix = "custom:"

    let entries: [IngredientEntry]
    /// Locale typed names are matched in (`exactMatch`, `search`).
    let locale: String
    private let byId: [String: IngredientEntry]
    private let bySourceId: [String: String]
    /// Folded source-locale name or alias -> id. Resolves V3 `import:` ids.
    private let bySourceName: [String: String]
    /// Folded name or alias in `locale` -> id. Keys owned by two entries are left out.
    private let byLocaleName: [String: String]

    init(entries: [IngredientEntry], locale: String = RegionalContext.contentLocale) {
        self.entries = entries
        self.locale = locale
        var byId: [String: IngredientEntry] = [:]
        var bySourceId: [String: String] = [:]
        for entry in entries {
            byId[entry.id] = entry
            for source in entry.sourceIds { bySourceId[source] = entry.id }
        }
        self.byId = byId
        self.bySourceId = bySourceId
        self.bySourceName = Self.unambiguousNames(entries, locale: IngredientEntry.sourceLocale)
        self.byLocaleName = Self.unambiguousNames(entries, locale: locale)
    }

    private static func unambiguousNames(_ entries: [IngredientEntry], locale: String) -> [String: String] {
        var owners: [String: Set<String>] = [:]
        for entry in entries {
            for name in [entry.name(in: locale)] + entry.aliases(in: locale) {
                let key = fold(name)
                guard !key.isEmpty else { continue }
                owners[key, default: []].insert(entry.id)
            }
        }
        return owners.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    init(data: Data, locale: String = RegionalContext.contentLocale) throws {
        let file = try JSONDecoder().decode(IngredientDictionaryFile.self, from: data)
        self.init(entries: file.ingredients, locale: locale)
    }

    static let shared: IngredientDictionary = {
        for bundle in [Bundle.main, Bundle(for: IngredientDictionaryBundleToken.self)] {
            let url = bundle.url(forResource: "ingredients.v2", withExtension: "json", subdirectory: "Recipes")
                ?? bundle.url(forResource: "ingredients.v2", withExtension: "json")
            if let url, let data = try? Data(contentsOf: url), let dictionary = try? IngredientDictionary(data: data) {
                return dictionary
            }
        }
        return IngredientDictionary(entries: [])
    }()

    func entry(_ id: String) -> IngredientEntry? { byId[id] }

    /// Dictionary id for a recipe, grocery or pantry id. Custom ids pass through. Nil otherwise.
    func canonicalId(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        if byId[id] != nil { return id }
        if let source = bySourceId[id] { return source }
        if Self.isCustom(id) { return id.lowercased() }
        if id.hasPrefix("import:") { return bySourceName[Self.fold(String(id.dropFirst("import:".count)))] }
        return nil
    }

    /// Comparison key. Two lines are the same ingredient only when their keys are equal.
    /// Unresolved ids keep their raw value, so they can never collide with a pantry row.
    func matchKey(_ raw: String) -> String {
        canonicalId(raw) ?? "unresolved:\(raw)"
    }

    func sameIngredient(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = canonicalId(lhs), let right = canonicalId(rhs) else { return false }
        return left == right
    }

    /// Suggestions for the controlled add flow. The user still picks the row; this never merges.
    func search(_ query: String, including extra: [IngredientEntry] = [], limit: Int = 12) -> [IngredientEntry] {
        let needle = Self.fold(query)
        let pool = extra + entries
        guard !needle.isEmpty else { return Array(pool.prefix(limit)) }
        var seen = Set<String>()
        var ranked: [(entry: IngredientEntry, rank: Int)] = []
        for entry in pool where !seen.contains(entry.id) {
            seen.insert(entry.id)
            var rank = Int.max
            for key in ([entry.name(in: locale)] + entry.aliases(in: locale)).map(Self.fold) {
                if key == needle { rank = min(rank, 0) }
                else if key.hasPrefix(needle) { rank = min(rank, 1) }
                else if key.contains(needle) { rank = min(rank, 2) }
            }
            if rank != Int.max { ranked.append((entry, rank)) }
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.entry.name(in: locale).compare(rhs.entry.name(in: locale), locale: Locale(identifier: locale)) == .orderedAscending
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// The exact dictionary row for a name typed in `locale`, if the dictionary declares one.
    func exactMatch(for name: String) -> IngredientEntry? {
        byLocaleName[Self.fold(name)].flatMap { byId[$0] }
    }

    static func isCustom(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard lower.hasPrefix(customPrefix) else { return false }
        return UUID(uuidString: String(lower.dropFirst(customPrefix.count))) != nil
    }

    /// A new user-created ingredient. The id is random, never derived from the typed text,
    /// and the server accepts it only through `POST /v1/households/:id/ingredients`.
    static func newCustomId() -> String {
        customPrefix + UUID().uuidString.lowercased()
    }

    /// Same folding as the server: Turkish letters to ASCII, only [a-z0-9] kept.
    static func fold(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased()
            .decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "ı", with: "i")
        var folded = ""
        for scalar in lowered.unicodeScalars where scalar.isASCII {
            let value = scalar.value
            if (0x61...0x7A).contains(value) || (0x30...0x39).contains(value) {
                folded.unicodeScalars.append(scalar)
            }
        }
        return folded
    }
}

private final class IngredientDictionaryBundleToken {}

private struct IngredientDictionaryFile: Decodable {
    var version: Int
    var sourceLocale: String?
    var ingredients: [IngredientEntry]
}
