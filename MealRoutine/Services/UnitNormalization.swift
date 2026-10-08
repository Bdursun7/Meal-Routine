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

/// Structured unit codes. Stored on recipe, grocery and pantry rows; shared with the server's
/// `pantryUnits.ts`. Display goes through `UnitLabels` (`unit.<code>` keys), never the raw code.
///
/// Conversion is exact only: mass through grams (1 oz = 28.349523125 g, 1 lb = 453.59237 g) and
/// volume through millilitres. Spoons and cups are not converted because their size differs by
/// measurement system (US cup 236.6 ml, metric cup 250 ml, Turkish su bardağı 200 ml). piece,
/// package, can and bottle never convert to mass or volume without ingredient data.
enum UnitCode: String, CaseIterable, Codable, Sendable {
    case g, kg, oz, lb
    case ml, l
    case piece, tsp, tbsp, cup, package, can, bottle, clove, pinch, slice, sprig
    case toTaste

    var family: UnitFamily? {
        switch self {
        case .g, .kg, .oz, .lb: .mass
        case .ml, .l: .volume
        default: nil
        }
    }

    var basePerUnit: Double {
        switch self {
        case .kg, .l: 1_000
        case .oz: 28.349523125
        case .lb: 453.59237
        default: 1
        }
    }

    var isImperial: Bool { self == .oz || self == .lb }

    /// The code and language-neutral abbreviations.
    var aliases: [String] {
        switch self {
        case .g: ["g", "gr", "gm"]
        case .kg: ["kg", "kgs"]
        case .oz: ["oz"]
        case .lb: ["lb", "lbs"]
        case .ml: ["ml", "mls"]
        case .l: ["l", "lt", "ltr"]
        case .piece: ["piece", "pc", "pcs"]
        case .tsp: ["tsp"]
        case .tbsp: ["tbsp"]
        case .cup: ["cup"]
        case .package: ["package", "pkg"]
        case .can: ["can"]
        case .bottle: ["bottle"]
        case .clove: ["clove"]
        case .pinch: ["pinch"]
        case .slice: ["slice"]
        case .sprig: ["sprig"]
        case .toTaste: ["toTaste", "to-taste"]
        }
    }

    /// Typed spellings keyed by language. Parsing accepts every language, so a recipe typed in
    /// Turkish still parses on an English device; no alias names two codes.
    var localeAliases: [String: [String]] {
        switch self {
        case .g: ["en": ["gram", "grams", "gramme", "grammes"], "tr": ["gram"]]
        case .kg: ["en": ["kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"], "tr": ["kilo", "kilogram"]]
        case .oz: ["en": ["ounce", "ounces"], "tr": ["ons"]]
        case .lb: ["en": ["pound", "pounds"], "tr": ["libre"]]
        case .ml: ["en": ["milliliter", "milliliters", "millilitre", "millilitres"], "tr": ["mililitre", "mililitres"]]
        case .l: ["en": ["liter", "liters", "litre", "litres"], "tr": ["litre"]]
        case .piece: ["en": ["pieces"], "tr": ["adet"]]
        case .tsp: ["en": ["teaspoon", "teaspoons"], "tr": ["tatlı kaşığı", "tatli kasigi", "tk"]]
        case .tbsp: ["en": ["tablespoon", "tablespoons"], "tr": ["yemek kaşığı", "yemek kasigi", "yk"]]
        case .cup: ["en": ["cups"], "tr": ["su bardağı", "su bardagi", "bardak"]]
        case .package: ["en": ["packages", "pack", "packs"], "tr": ["paket"]]
        case .can: ["en": ["cans", "tin", "tins"], "tr": ["kutu", "konserve"]]
        case .bottle: ["en": ["bottles"], "tr": ["şişe", "sise"]]
        case .clove: ["en": ["cloves"], "tr": ["diş", "dis"]]
        case .pinch: ["en": ["pinches"], "tr": ["tutam"]]
        case .slice: ["en": ["slices"], "tr": ["dilim"]]
        case .sprig: ["en": ["sprigs"], "tr": ["dal"]]
        case .toTaste: ["en": ["to taste"], "tr": ["damak tadına", "damak tadina"]]
        }
    }
}

/// Folds typed and catalog unit spellings onto one `UnitCode`.
///
/// The catalog itself only stores twelve codes (`g`, `kg`, `ml`, `l`, `piece`,
/// `tbsp`, `tsp`, `clove`, `toTaste`, `sprig`, `pinch`, `slice`). Unknown spellings keep a loose
/// code of their own and never merge with a known unit.
///
/// Only exact pairs convert: g ↔ kg ↔ oz ↔ lb and ml ↔ l. Spoons, cups, pinches, sprigs,
/// pieces, packages and “to taste” stay on their own code.
enum UnitNormalization {
    static func parse(_ raw: String) -> ParsedUnit {
        let key = fold(raw)
        if let unit = unitsByFoldedAlias[key] {
            return ParsedUnit(code: unit.rawValue, family: unit.family, basePerUnit: unit.basePerUnit)
        }
        return ParsedUnit(code: looseCode(raw), family: nil, basePerUnit: 1)
    }

    /// The structured code for a typed or stored unit, or nil when it is not a known unit.
    static func unitCode(_ raw: String) -> UnitCode? {
        unitsByFoldedAlias[fold(raw)]
    }

    /// Sum quantities that already belong in one merge bucket.
    ///
    /// A single canonical code keeps its own unit, so a week of only grams stays
    /// in grams even when the scaled total crosses a kilogram. Mixed codes in one
    /// family convert through the base unit, then pick grams or kilograms
    /// (millilitres or litres) from the total. A mass bucket written only in ounces and pounds
    /// stays imperial (ounces, or pounds from 16 oz).
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
        let imperial = units.allSatisfy { UnitCode(rawValue: $0.code)?.isImperial == true }
        return display(base: snapBase(base), family: family, imperial: imperial)
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

    private static func display(base: Double, family: UnitFamily, imperial: Bool) -> (quantity: Double?, code: String) {
        switch family {
        case .mass:
            if imperial {
                let ounces = base / UnitCode.oz.basePerUnit
                if ounces >= 16 {
                    return (snapBase(base / UnitCode.lb.basePerUnit), UnitCode.lb.rawValue)
                }
                return (snapBase(ounces), UnitCode.oz.rawValue)
            }
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

    private static let unitsByFoldedAlias: [String: UnitCode] = {
        var map: [String: UnitCode] = [:]
        for unit in UnitCode.allCases {
            for alias in unit.aliases + unit.localeAliases.keys.sorted().flatMap({ unit.localeAliases[$0] ?? [] }) {
                map[fold(alias)] = unit
            }
        }
        return map
    }()
}
