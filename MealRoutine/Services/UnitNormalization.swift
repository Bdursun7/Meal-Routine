import Foundation

/// Family of units that share a base and can be summed in V1.
enum UnitFamily: String, Equatable, Sendable {
    /// Base unit is the gram.
    case mass
    /// Base unit is the millilitre.
    case volume
}

/// A catalog or typed unit after spelling fold.
struct ParsedUnit: Equatable, Sendable {
    /// Stable code stored on a grocery row (`g`, `kg`, `piece`, `toTaste`, …).
    var code: String
    /// Set only for pairs V1 converts. Nil units never cross-convert.
    var family: UnitFamily?
    /// Multiply a quantity in `code` to reach the family base. `1` when there is no family.
    var basePerUnit: Double
}

/// Folds Turkish and English spellings of the units that actually appear in
/// `recipes.v1.json` onto one code.
///
/// The catalog itself only stores twelve codes (`g`, `kg`, `ml`, `l`, `piece`,
/// `tbsp`, `tsp`, `clove`, `toTaste`, `sprig`, `pinch`, `slice`). Aliases cover
/// those codes, the Turkish labels `UnitLabels` already shows, and the short
/// English variants of the same words (`gr`, `gram`, `mL`, `adet`, …).
///
/// V1 converts only exact metric pairs: gram ↔ kilogram and millilitre ↔ litre.
/// Spoons, pinches, sprigs, pieces, and “to taste” stay on their own code.
enum UnitNormalization {
    static func parse(_ raw: String) -> ParsedUnit {
        let key = fold(raw)
        if let spec = specsByFoldedAlias[key] {
            return ParsedUnit(code: spec.code, family: spec.family, basePerUnit: spec.basePerUnit)
        }
        return ParsedUnit(code: looseCode(raw), family: nil, basePerUnit: 1)
    }

    /// Sum quantities that already belong in one merge bucket.
    ///
    /// A single canonical code keeps its own unit, so a week of only grams stays
    /// in grams even when the scaled total crosses a kilogram. Mixed codes in one
    /// family convert through the base unit, then pick grams or kilograms
    /// (millilitres or litres) from the total.
    static func combine(quantities: [Double?], units: [ParsedUnit]) -> (quantity: Double?, code: String) {
        guard let first = units.first, quantities.count == units.count else {
            return (nil, "")
        }
        let codes = Set(units.map(\.code))
        if codes.count == 1 {
            let measured = quantities.compactMap { $0 }
            let quantity = measured.isEmpty ? nil : measured.reduce(0, +)
            return (quantity, first.code)
        }

        guard let family = first.family else {
            let measured = quantities.compactMap { $0 }
            let quantity = measured.isEmpty ? nil : measured.reduce(0, +)
            return (quantity, first.code)
        }

        var base = 0.0
        var measuredCount = 0
        for index in units.indices {
            guard let quantity = quantities[index] else { continue }
            base += snapBase(quantity * units[index].basePerUnit)
            measuredCount += 1
        }
        if measuredCount == 0 {
            return (nil, preferredCode(units))
        }
        return display(base: snapBase(base), family: family)
    }

    /// Match key for aliases. Letters and digits only, Turkish diacritics folded.
    static func fold(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "İ", with: "i")
        text = text.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !CharacterSet.nonBaseCharacters.contains(scalar) {
            scalars.append(scalar)
        }
        text = String(scalars)
        var folded = ""
        folded.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "ç": folded.append("c")
            case "ğ": folded.append("g")
            case "ı": folded.append("i")
            case "ö": folded.append("o")
            case "ş": folded.append("s")
            case "ü": folded.append("u")
            default:
                if character.isLetter || character.isNumber {
                    folded.append(character)
                }
            }
        }
        return folded
    }

    private static func display(base: Double, family: UnitFamily) -> (quantity: Double?, code: String) {
        switch family {
        case .mass:
            if base >= 1_000 {
                return (base / 1_000, "kg")
            }
            return (base, "g")
        case .volume:
            if base >= 1_000 {
                return (base / 1_000, "l")
            }
            return (base, "ml")
        }
    }

    private static func preferredCode(_ units: [ParsedUnit]) -> String {
        var counts: [String: Int] = [:]
        for unit in units {
            counts[unit.code, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }?.key ?? units[0].code
    }

    /// Nearest milligram or microlitre, so 1.2 kg survives a trip through grams.
    private static func snapBase(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }

    private static func looseCode(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "İ", with: "i")
        text = text.lowercased()
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private struct Spec {
        var code: String
        var family: UnitFamily?
        var basePerUnit: Double
        var aliases: [String]
    }

    /// Aliases are the spellings we fold. Each code is included as its own alias.
    private static let specs: [Spec] = [
        Spec(code: "g", family: .mass, basePerUnit: 1, aliases: [
            "g", "gr", "gm", "gram", "grams", "gramme", "grammes",
        ]),
        Spec(code: "kg", family: .mass, basePerUnit: 1_000, aliases: [
            "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes",
        ]),
        Spec(code: "ml", family: .volume, basePerUnit: 1, aliases: [
            "ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres", "mililitre", "mililitres",
        ]),
        Spec(code: "l", family: .volume, basePerUnit: 1_000, aliases: [
            "l", "lt", "ltr", "liter", "liters", "litre", "litres",
        ]),
        Spec(code: "piece", family: nil, basePerUnit: 1, aliases: [
            "piece", "pieces", "pc", "pcs", "adet",
        ]),
        Spec(code: "tbsp", family: nil, basePerUnit: 1, aliases: [
            "tbsp", "tablespoon", "tablespoons", "yemek kaşığı", "yemek kasigi", "yk",
        ]),
        Spec(code: "tsp", family: nil, basePerUnit: 1, aliases: [
            "tsp", "teaspoon", "teaspoons", "tatlı kaşığı", "tatli kasigi", "tk",
        ]),
        Spec(code: "clove", family: nil, basePerUnit: 1, aliases: [
            "clove", "cloves", "diş", "dis",
        ]),
        Spec(code: "pinch", family: nil, basePerUnit: 1, aliases: [
            "pinch", "pinches", "tutam",
        ]),
        Spec(code: "slice", family: nil, basePerUnit: 1, aliases: [
            "slice", "slices", "dilim",
        ]),
        Spec(code: "sprig", family: nil, basePerUnit: 1, aliases: [
            "sprig", "sprigs", "dal",
        ]),
        Spec(code: "toTaste", family: nil, basePerUnit: 1, aliases: [
            "toTaste", "to taste", "to-taste", "damak tadına", "damak tadina",
        ]),
    ]

    private static let specsByFoldedAlias: [String: Spec] = {
        var map: [String: Spec] = [:]
        for spec in specs {
            for alias in spec.aliases {
                map[fold(alias)] = spec
            }
        }
        return map
    }()
}
