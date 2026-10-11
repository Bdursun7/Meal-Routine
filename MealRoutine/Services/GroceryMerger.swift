import Foundation

struct GrocerySourceLine: Equatable, Sendable {
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
}

struct MergedGroceryLine: Equatable, Sendable, Identifiable {
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
    var hasUnitConflict: Bool

    var id: String { "\(ingredientId)|\(unit)" }
}

/// Where one shopping line came from. The Market card shows this instead of
/// calling every non-plan row "Elle eklendi".
enum GroceryLineSource: String, Equatable, Sendable {
    case plan
    case shortfall
    case threshold
    case cookGap
    case typed

    var title: String {
        switch self {
        case .plan: "Plan"
        case .shortfall: "Evdekiler eksiği"
        case .threshold: "Eşik"
        case .cookGap: "Pişirme eksiği"
        case .typed: "Elle eklendi"
        }
    }

    var sort: Int {
        switch self {
        case .plan: 0
        case .shortfall: 1
        case .threshold: 2
        case .cookGap: 3
        case .typed: 4
        }
    }

    /// Empty `stored` keeps rows saved before the source column existed.
    /// A manual catalog id is a Bitti shortfall. Only `manual:` was typed with +.
    /// A cook-gap key is never the shortfall label, even when an older write stored `shortfall`.
    static func resolve(ingredientId: String, isManual: Bool, stored: String) -> GroceryLineSource {
        if ingredientId.hasPrefix("pantry-cook:") { return .cookGap }
        if let known = GroceryLineSource(rawValue: stored), !stored.isEmpty { return known }
        if !isManual { return .plan }
        if ingredientId.hasPrefix("manual:") { return .typed }
        return .shortfall
    }
}

/// Groups shopping lines by dictionary canonical ingredient id.
///
/// User-approved 2026-10-11: `tomatoes` and `tomato` are one automatic row.
/// Display names never decide identity, so `cherry-tomato` stays separate.
/// Equivalent spellings (`g` / `gr` / `gram`, `adet` / `piece`, `yemek kaşığı` / `tbsp`)
/// sum into one row. Gram converts with kilogram, and millilitre with litre.
/// Anything else with the same canonical id stays on its own row and is flagged.
enum GroceryMerger {
    static func merge(
        _ lines: [GrocerySourceLine],
        dictionary: IngredientDictionary = .shared
    ) -> [MergedGroceryLine] {
        let grouped = Dictionary(grouping: lines) {
            shoppingIngredientId($0.ingredientId, dictionary: dictionary)
        }
        var merged: [MergedGroceryLine] = []
        merged.reserveCapacity(grouped.count)

        for (ingredientId, group) in grouped {
            let parsed = group.map { line in
                (line: line, unit: UnitNormalization.parse(line.unit))
            }
            let buckets = Dictionary(grouping: parsed) { item in
                bucketKey(for: item.unit)
            }
            let hasConflict = buckets.count > 1

            for key in buckets.keys.sorted() {
                let unitLines = buckets[key] ?? []
                let combined = UnitNormalization.combine(
                    quantities: unitLines.map(\.line.quantity),
                    units: unitLines.map(\.unit)
                )
                let nameTR = dictionary.entry(ingredientId)?.name
                    ?? unitLines.first(where: { !$0.line.nameTR.isEmpty })?.line.nameTR
                    ?? unitLines.first?.line.nameEN
                    ?? ingredientId
                let nameEN = unitLines.first(where: { !$0.line.nameEN.isEmpty })?.line.nameEN ?? ""
                merged.append(
                    MergedGroceryLine(
                        ingredientId: ingredientId,
                        nameTR: nameTR,
                        nameEN: nameEN,
                        quantity: roundedQuantity(combined.quantity),
                        unit: combined.code,
                        hasUnitConflict: hasConflict
                    )
                )
            }
        }

        return merged.sorted { lhs, rhs in
            let nameOrder = lhs.nameTR.localizedStandardCompare(rhs.nameTR)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.unit < rhs.unit
        }
    }

    /// Thousandths, the same snap as pantry and unit conversion.
    /// `0.1 + 0.2` becomes `0.3`. 125 g + 1 kg stays `1.125` kg.
    static func roundedQuantity(_ quantity: Double?) -> Double? {
        guard let quantity else { return nil }
        return (quantity * 1_000).rounded() / 1_000
    }

    /// Canonical unit code. Safe to store and to compare across rebuilds.
    static func normalize(_ unit: String) -> String {
        UnitNormalization.parse(unit).code
    }

    /// Identity of one automatic shopping row across rebuilds.
    ///
    /// The ingredient half is the dictionary canonical id (`tomatoes` → `tomato`).
    /// An id the dictionary does not know stays as written, so two display names
    /// never collapse on their own. Mass (`g` / `kg`) and volume (`ml` / `l`)
    /// share a bucket. Every other unit stays on its own canonical code.
    static func rowIdentity(
        ingredientId: String,
        unit: String,
        dictionary: IngredientDictionary = .shared
    ) -> String {
        "\(shoppingIngredientId(ingredientId, dictionary: dictionary))|\(unitBucket(unit))"
    }

    /// Bucket stored in `pantry-auto:` / `pantry-cook:` keys and in `rowIdentity`.
    /// Accepts a real unit (`kg`, `adet`) or a bucket already produced here.
    static func unitBucket(_ unit: String) -> String {
        if unit.hasPrefix("family:") || unit.hasPrefix("unit:") { return unit }
        if unit == "mass" { return "family:mass" }
        if unit == "volume" { return "family:volume" }
        return bucketKey(for: UnitNormalization.parse(unit))
    }

    /// Catalog id inside a plan row or a `pantry-auto:` / `pantry-cook:` key.
    /// `manual:` is returned unchanged so a typed row is not renamed.
    static func bareIngredientId(_ stored: String) -> String {
        if stored.hasPrefix("pantry-auto:") {
            return beforeUnit(String(stored.dropFirst("pantry-auto:".count)))
        }
        if stored.hasPrefix("pantry-cook:") {
            let rest = String(stored.dropFirst("pantry-cook:".count))
            let head = beforeUnit(rest)
            guard let colon = head.firstIndex(of: ":") else { return head }
            return String(head[head.index(after: colon)...])
        }
        return stored
    }

    /// Dictionary id when one exists. Otherwise the bare id, never the display name.
    static func shoppingIngredientId(
        _ raw: String,
        dictionary: IngredientDictionary = .shared
    ) -> String {
        let bare = bareIngredientId(raw)
        if bare.hasPrefix("manual:") { return bare }
        return dictionary.canonicalId(bare) ?? bare
    }

    private static func beforeUnit(_ value: String) -> String {
        guard let bar = value.lastIndex(of: "|") else { return value }
        return String(value[..<bar])
    }

    private static func bucketKey(for unit: ParsedUnit) -> String {
        if let family = unit.family {
            return "family:\(family.rawValue)"
        }
        return "unit:\(unit.code)"
    }

    /// Canonical replenishment key. `tomatoes` and `piece` / `adet` share one key.
    static func pantryAutoKey(
        ingredientId: String,
        unit: String,
        dictionary: IngredientDictionary = .shared
    ) -> String {
        let id = shoppingIngredientId(ingredientId, dictionary: dictionary)
        return "pantry-auto:\(id)|\(unitBucket(unit))"
    }

    static func keyUnitSuffix(_ key: String) -> String {
        guard let bar = key.lastIndex(of: "|") else { return "" }
        return String(key[key.index(after: bar)...])
    }
}

/// One stored shopping row handed to the legacy-shortfall reconcile.
struct LegacyGroceryRow: Equatable, Sendable {
    var id: UUID
    var ingredientId: String
    var quantity: Double?
    var unit: String
    var isChecked: Bool
    var isManual: Bool
    var sourceRaw: String
}

/// Rewrite one shortfall identity onto `pantry-auto:<canonical>|<bucket>` and drop the extras.
struct LegacyShortfallUpdate: Equatable, Sendable {
    var keepID: UUID
    var ingredientId: String
    var quantity: Double
    var unit: String
    var isChecked: Bool
    var sourceRaw: String
    var deleteIDs: [UUID]
}

/// Which household item keys a shortfall collapse updates, and which it retires.
struct GroceryBoardSyncPlan: Equatable, Sendable {
    var wireKey: String
    var removeKeys: [String]
}

/// Rows saved before the canonical key still sit in the store.
///
/// A shortfall is a set, not a delta. Two rows for the same canonical id and
/// unit bucket are two writes of one need (`pantry-auto:tomatoes|piece` and a
/// Bitti row of `tomatoes`, for example). Adding 1 and 2 would buy the need
/// twice. The larger amount in the shared unit family is the set that still
/// covers the smaller one, so that amount is kept. Grocery rows have no
/// timestamp; when the amounts match, the row already on the canonical key
/// wins, then a checked row, then the lowest id.
///
/// A check is kept only when a merged row with that same amount was checked.
/// A check on a different amount belonged to a different set and is not moved.
/// `manual:` typed rows and `pantry-cook:` gaps are not shortfall rows.
enum GroceryShortfallCollapse {
    static func plan(
        _ rows: [LegacyGroceryRow],
        dictionary: IngredientDictionary = .shared
    ) -> (updates: [LegacyShortfallUpdate], cookGapIDs: [UUID]) {
        let cookGapIDs = rows.compactMap { row -> UUID? in
            guard row.ingredientId.hasPrefix("pantry-cook:") else { return nil }
            return row.sourceRaw == GroceryLineSource.cookGap.rawValue ? nil : row.id
        }
        let candidates = rows.filter(isShortfall)
        let grouped = Dictionary(grouping: candidates) {
            GroceryMerger.rowIdentity(ingredientId: $0.ingredientId, unit: $0.unit, dictionary: dictionary)
        }
        var updates: [LegacyShortfallUpdate] = []
        for group in grouped.values {
            guard let update = collapse(group, dictionary: dictionary) else { continue }
            updates.append(update)
        }
        updates.sort { $0.ingredientId < $1.ingredientId }
        return (updates, cookGapIDs.sorted { $0.uuidString < $1.uuidString })
    }

    /// The household board has no rename. Reuse a legacy pantry-auto key when it
    /// is the only one, so the set does not open a second server row. When the
    /// canonical key is already there, keep that one and retire the other
    /// pantry-auto keys for the same bucket. Deleted local rows also retire
    /// their `manual:<uuid>` check keys. Plan keys are left alone.
    static func boardSync(
        canonicalKey: String,
        existingKeys: [String],
        deletedIDs: [UUID],
        dictionary: IngredientDictionary = .shared
    ) -> GroceryBoardSyncPlan {
        let matches = existingKeys.filter { key in
            key.hasPrefix("pantry-auto:") && sameAuto(key, canonicalKey, dictionary: dictionary)
        }
        let wire = matches.first { $0 == canonicalKey } ?? matches.first ?? canonicalKey
        var remove = matches.filter { $0 != wire }
        for id in deletedIDs {
            remove.append("manual:\(id.uuidString)")
        }
        remove = Array(Set(remove)).filter { $0 != wire }.sorted()
        return GroceryBoardSyncPlan(wireKey: wire, removeKeys: remove)
    }

    /// Larger set in one family. Used by the card when two shortfall parts
    /// have not been rewritten yet, so the label is never repeated.
    static func largestSet(
        _ rows: [(quantity: Double?, unit: String, isChecked: Bool)]
    ) -> (quantity: Double?, unit: String, isChecked: Bool)? {
        guard let winner = rows.max(by: { base($0.quantity, $0.unit) < base($1.quantity, $1.unit) }) else {
            return nil
        }
        guard let quantity = winner.quantity else { return nil }
        let amount = base(quantity, winner.unit)
        let checked = rows.contains { $0.isChecked && abs(base($0.quantity, $0.unit) - amount) < 0.000_5 }
        return (GroceryMerger.roundedQuantity(quantity), GroceryMerger.normalize(winner.unit), checked)
    }

    private static func collapse(
        _ group: [LegacyGroceryRow],
        dictionary: IngredientDictionary
    ) -> LegacyShortfallUpdate? {
        let measured = group.filter { $0.quantity != nil }
        guard !measured.isEmpty else { return nil }
        let sample = measured[0]
        let canonical = GroceryMerger.pantryAutoKey(
            ingredientId: sample.ingredientId,
            unit: sample.unit,
            dictionary: dictionary
        )
        let winner = measured.sorted { lhs, rhs in
            let left = base(lhs.quantity, lhs.unit)
            let right = base(rhs.quantity, rhs.unit)
            if left != right { return left > right }
            let leftCanonical = lhs.ingredientId == canonical
            let rightCanonical = rhs.ingredientId == canonical
            if leftCanonical != rightCanonical { return leftCanonical }
            if lhs.isChecked != rhs.isChecked { return lhs.isChecked }
            return lhs.id.uuidString < rhs.id.uuidString
        }[0]
        guard let quantity = winner.quantity else { return nil }
        let amount = base(quantity, winner.unit)
        let checked = measured.contains { $0.isChecked && abs(base($0.quantity, $0.unit) - amount) < 0.000_5 }
        let unit = GroceryMerger.normalize(winner.unit)
        let source = winner.sourceRaw == GroceryLineSource.threshold.rawValue
            ? GroceryLineSource.threshold.rawValue
            : GroceryLineSource.shortfall.rawValue
        let storedQuantity = GroceryMerger.roundedQuantity(quantity) ?? quantity
        let deleteIDs = group.map(\.id).filter { $0 != winner.id }.sorted { $0.uuidString < $1.uuidString }
        let already =
            group.count == 1
            && winner.ingredientId == canonical
            && winner.unit == unit
            && winner.isChecked == checked
            && winner.sourceRaw == source
            && winner.quantity == storedQuantity
        if already { return nil }
        return LegacyShortfallUpdate(
            keepID: winner.id,
            ingredientId: canonical,
            quantity: storedQuantity,
            unit: unit,
            isChecked: checked,
            sourceRaw: source,
            deleteIDs: deleteIDs
        )
    }

    private static func isShortfall(_ row: LegacyGroceryRow) -> Bool {
        if row.ingredientId.hasPrefix("pantry-cook:") || row.ingredientId.hasPrefix("manual:") { return false }
        if row.ingredientId.hasPrefix("pantry-auto:") { return true }
        return row.isManual
    }

    private static func sameAuto(
        _ lhs: String,
        _ rhs: String,
        dictionary: IngredientDictionary
    ) -> Bool {
        GroceryMerger.rowIdentity(ingredientId: lhs, unit: GroceryMerger.keyUnitSuffix(lhs), dictionary: dictionary)
            == GroceryMerger.rowIdentity(ingredientId: rhs, unit: GroceryMerger.keyUnitSuffix(rhs), dictionary: dictionary)
    }

    private static func base(_ quantity: Double?, _ unit: String) -> Double {
        guard let quantity else { return -.infinity }
        return quantity * UnitNormalization.parse(unit).basePerUnit
    }
}

/// Vetoed evenings leave the shopping list. A skip keeps the recipe and its rows.
enum GroceryMealAudit {
    static func shops(isSkipped: Bool, isVetoed: Bool) -> Bool {
        // A skip keeps the recipe on the list. Only a veto removes it.
        if isSkipped { return !isVetoed }
        return !isVetoed
    }
}

/// Integer written to `shared_grocery_items.quantity` (migration 0008).
enum GrocerySyncQuantity {
    static func whole(_ quantity: Double?) -> Int {
        guard let quantity, quantity > 0 else { return 1 }
        return max(1, Int(quantity.rounded()))
    }
}
