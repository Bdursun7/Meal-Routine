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
    case typed

    var title: String {
        switch self {
        case .plan: "Plan"
        case .shortfall: "Evdekiler eksiği"
        case .threshold: "Eşik"
        case .typed: "Elle eklendi"
        }
    }

    var sort: Int {
        switch self {
        case .plan: 0
        case .shortfall: 1
        case .threshold: 2
        case .typed: 3
        }
    }

    /// Empty `stored` keeps rows saved before the source column existed.
    /// A manual catalog id is a Bitti shortfall. Only `manual:` was typed with +.
    static func resolve(ingredientId: String, isManual: Bool, stored: String) -> GroceryLineSource {
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
