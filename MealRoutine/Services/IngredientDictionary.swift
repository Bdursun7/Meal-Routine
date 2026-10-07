import Foundation

/// One row of the central V5 ingredient dictionary (`Recipes/ingredients.v1.json`).
/// The server seeds the same file in migration `0012`; the server copy is authoritative.
struct IngredientEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var synonyms: [String]
    var sourceIds: [String]

    init(id: String, name: String, synonyms: [String] = [], sourceIds: [String] = []) {
        self.id = id
        self.name = name
        self.synonyms = synonyms
        self.sourceIds = sourceIds
    }
}

/// Recipe, grocery and pantry lines meet on `ingredientId`. Display names never decide identity.
/// A catalog id resolves through `sourceIds`; a V3 `import:<folded name>` id resolves only when that
/// name is an unambiguous dictionary name or synonym. `custom:<uuid>` ids are user-created and
/// match only themselves. Everything else, including `manual:` grocery rows, matches nothing.
struct IngredientDictionary: Sendable {
    static let customPrefix = "custom:"

    let entries: [IngredientEntry]
    private let byId: [String: IngredientEntry]
    private let bySourceId: [String: String]
    private let byName: [String: String]

    init(entries: [IngredientEntry]) {
        self.entries = entries
        var byId: [String: IngredientEntry] = [:]
        var bySourceId: [String: String] = [:]
        var owners: [String: Set<String>] = [:]
        for entry in entries {
            byId[entry.id] = entry
            for source in entry.sourceIds { bySourceId[source] = entry.id }
            for name in [entry.name] + entry.synonyms {
                let key = Self.fold(name)
                guard !key.isEmpty else { continue }
                owners[key, default: []].insert(entry.id)
            }
        }
        self.byId = byId
        self.bySourceId = bySourceId
        self.byName = owners.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(IngredientDictionaryFile.self, from: data)
        self.init(entries: file.ingredients)
    }

    static let shared: IngredientDictionary = {
        for bundle in [Bundle.main, Bundle(for: IngredientDictionaryBundleToken.self)] {
            let url = bundle.url(forResource: "ingredients.v1", withExtension: "json", subdirectory: "Recipes")
                ?? bundle.url(forResource: "ingredients.v1", withExtension: "json")
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
        if id.hasPrefix("import:") { return byName[Self.fold(String(id.dropFirst("import:".count)))] }
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
            for key in ([entry.name] + entry.synonyms).map(Self.fold) {
                if key == needle { rank = min(rank, 0) }
                else if key.hasPrefix(needle) { rank = min(rank, 1) }
                else if key.contains(needle) { rank = min(rank, 2) }
            }
            if rank != Int.max { ranked.append((entry, rank)) }
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.entry.name.compare(rhs.entry.name, locale: Locale(identifier: "tr_TR")) == .orderedAscending
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// The exact dictionary row for a typed name, if the dictionary declares one.
    func exactMatch(for name: String) -> IngredientEntry? {
        byName[Self.fold(name)].flatMap { byId[$0] }
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
    var ingredients: [IngredientEntry]
}
