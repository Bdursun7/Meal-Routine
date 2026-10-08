import Foundation

/// Unit display names. Rows store `UnitCode` raw values; the label is looked up per display
/// language (`unit.<code>`). Unknown loose codes are shown as typed.
enum UnitLabels {
    static func label(_ unit: String) -> String {
        guard let code = UnitCode(rawValue: unit) ?? UnitCode.allCases.first(where: { $0.rawValue.lowercased() == unit.lowercased() }) else {
            return unit
        }
        return label(code)
    }

    static func label(_ code: UnitCode) -> String {
        switch code {
        case .g: L10n.text("unit.g", "g")
        case .kg: L10n.text("unit.kg", "kg")
        case .oz: L10n.text("unit.oz", "oz")
        case .lb: L10n.text("unit.lb", "lb")
        case .ml: L10n.text("unit.ml", "ml")
        case .l: L10n.text("unit.l", "l")
        case .piece: L10n.text("unit.piece", "adet")
        case .tsp: L10n.text("unit.tsp", "tatlı kaşığı")
        case .tbsp: L10n.text("unit.tbsp", "yemek kaşığı")
        case .cup: L10n.text("unit.cup", "su bardağı")
        case .package: L10n.text("unit.package", "paket")
        case .can: L10n.text("unit.can", "kutu")
        case .bottle: L10n.text("unit.bottle", "şişe")
        case .clove: L10n.text("unit.clove", "diş")
        case .pinch: L10n.text("unit.pinch", "tutam")
        case .slice: L10n.text("unit.slice", "dilim")
        case .sprig: L10n.text("unit.sprig", "dal")
        case .toTaste: L10n.text("unit.toTaste", "damak tadına")
        }
    }
}

/// Quantities in the display locale. Decimal separators always come from the formatter.
enum QuantityFormat {
    static func string(_ value: Double?, locale: Locale = RegionalContext.displayLocale) -> String {
        guard let value, value.isFinite else { return "" }
        let formatter = numberFormatter(locale)
        // A stored thousandth (125 g written as 1.125 kg) keeps three places.
        // Anything finer, such as a raw scaled spice, stays at two so 2.828… is still 2,83.
        let thousandth = (value * 1_000).rounded() / 1_000
        formatter.maximumFractionDigits = abs(value - thousandth) < 0.000_000_1 ? 3 : 2
        formatter.minimumFractionDigits = 0
        if let rendered = formatter.string(from: NSNumber(value: value)),
           !rendered.isEmpty,
           let roundTrip = parse(rendered, locale: locale),
           abs(roundTrip - value) < 0.006,
           value == 0 || roundTrip != 0 {
            return rendered
        }
        formatter.maximumFractionDigits = 3
        if let rendered = formatter.string(from: NSNumber(value: value)),
           value == 0 || parse(rendered, locale: locale) != 0 {
            return rendered
        }
        formatter.maximumFractionDigits = 10
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    /// Reads a typed amount. The display locale's decimal separator is accepted, and so is `.`
    /// or `,` when the text has exactly one separator, so `1,25` and `1.25` both mean 1.25 on a
    /// Turkish device. Grouping separators are not accepted (`1.500` would be ambiguous).
    static func parse(_ text: String, locale: Locale = RegionalContext.displayLocale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        guard !trimmed.isEmpty else { return nil }
        let separators = trimmed.filter { $0 == "." || $0 == "," }
        guard separators.count <= 1 else { return nil }
        let formatter = numberFormatter(locale)
        let decimal = formatter.decimalSeparator ?? "."
        var canonical = trimmed
        if let separator = separators.first, String(separator) != decimal {
            canonical = trimmed.replacingOccurrences(of: String(separator), with: decimal)
        }
        if canonical.hasSuffix(decimal) { canonical.removeLast(decimal.count) }
        if canonical.hasPrefix(decimal) { canonical = "0" + canonical }
        guard !canonical.isEmpty, let number = formatter.number(from: canonical) else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    static func quantityAndUnit(quantity: Double?, unit: String, locale: Locale = RegionalContext.displayLocale) -> String {
        let label = UnitLabels.label(unit)
        if unit.lowercased() == "totaste" || quantity == nil {
            return label
        }
        let amount = string(quantity, locale: locale)
        if amount.isEmpty { return label }
        return "\(amount) \(label)"
    }

    private static func numberFormatter(_ locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        // Grouping (1.500) does not round-trip through Double and would save as 1.5.
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        return formatter
    }
}

enum DifficultyLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "easy": L10n.text("difficulty.easy", "Kolay")
        case "medium": L10n.text("difficulty.medium", "Orta")
        case "hard": L10n.text("difficulty.hard", "Zor")
        case "unknown": L10n.text("difficulty.unknown", "Bilinmiyor")
        default: raw
        }
    }
}

enum DietLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "vegetarian": L10n.text("diet.vegetarian", "Vejetaryen")
        case "vegan": L10n.text("diet.vegan", "Vegan")
        case "gluten-free": L10n.text("diet.glutenFree", "Glutensiz")
        case "pescatarian": L10n.text("diet.pescatarian", "Pesketaryen")
        default: raw
        }
    }
}

enum CategoryLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "main": L10n.text("category.main", "Ana yemek")
        case "soup": L10n.text("category.soup", "Çorba")
        case "salad": L10n.text("category.salad", "Salata")
        case "breakfast": L10n.text("category.breakfast", "Kahvaltı")
        default: raw
        }
    }
}

/// Cuisine country names from the ISO region code, in the display language.
enum RegionLabel {
    static func label(_ code: String, locale: Locale = RegionalContext.displayLocale) -> String {
        locale.localizedString(forRegionCode: code.uppercased()) ?? code
    }
}

/// Household size accepted by onboarding and Profile.
enum HouseholdSizeLimits {
    static let minimum = 1
    static let maximum = 8
    static var range: ClosedRange<Int> { minimum...maximum }

    static func clamped(_ value: Int) -> Int {
        min(max(value, minimum), maximum)
    }
}

/// Evenings planned per week. The stored range is 1...7, matching `MealRecommender.eveningCap`.
enum EveningCountOptions {
    static let minimum = 1
    static let maximum = 7
    static var values: [Int] { Array(minimum...maximum) }

    /// Chip and picker label. Always a phrase, never a raw count or type dump.
    static func label(_ count: Int) -> String {
        let value = min(max(count, minimum), maximum)
        return L10n.format("evenings.count", "%ld akşam", value)
    }
}

/// Max cook time choices. Default is 60. Values outside the list resolve to that default.
enum CookTimeOptions {
    static let minutes = [30, 45, 60, 90]
    static let defaultMinutes = 60

    static func resolved(_ value: Int) -> Int {
        minutes.contains(value) ? value : defaultMinutes
    }

    static func label(_ minutes: Int) -> String {
        L10n.format("minutes.short", "%ld dk", minutes)
    }
}
