import Foundation

enum UnitLabels {
    static func turkish(_ unit: String) -> String {
        switch unit.lowercased() {
        case "g": "g"
        case "kg": "kg"
        case "ml": "ml"
        case "l": "l"
        case "piece": "adet"
        case "tbsp": "yemek kaşığı"
        case "tsp": "tatlı kaşığı"
        case "clove": "diş"
        case "totaste": "damak tadına"
        case "sprig": "dal"
        case "pinch": "tutam"
        case "slice": "dilim"
        default: unit
        }
    }
}

enum QuantityFormat {
    static func string(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        // Grouping (1.500) does not round-trip through Double and would save as 1.5.
        formatter.usesGroupingSeparator = false
        // Two places so a summed 1.25 kg is not rounded to the nearest tenth.
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        if let rendered = formatter.string(from: NSNumber(value: value)),
           !rendered.isEmpty,
           let roundTrip = parsed(rendered),
           abs(roundTrip - value) < 0.006,
           value == 0 || roundTrip != 0 {
            return rendered
        }
        return plain(value)
    }

    private static func parsed(_ rendered: String) -> Double? {
        let normalized = rendered
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(normalized)
    }

    private static func plain(_ value: Double) -> String {
        let raw = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
        var text = raw
        while text.contains(".") && text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        if parsed(text) == 0, value != 0 {
            return String(value).replacingOccurrences(of: ".", with: ",")
        }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func quantityAndUnit(quantity: Double?, unit: String) -> String {
        let label = UnitLabels.turkish(unit)
        if unit.lowercased() == "totaste" || quantity == nil {
            return label
        }
        let amount = string(quantity)
        if amount.isEmpty { return label }
        return "\(amount) \(label)"
    }
}

enum DifficultyLabel {
    static func turkish(_ raw: String) -> String {
        switch raw {
        case "easy": "Kolay"
        case "medium": "Orta"
        case "hard": "Zor"
        case "unknown": "Bilinmiyor"
        default: raw
        }
    }
}

enum DietLabel {
    static func turkish(_ raw: String) -> String {
        switch raw {
        case "vegetarian": "Vejetaryen"
        case "vegan": "Vegan"
        case "gluten-free": "Glutensiz"
        case "pescatarian": "Pesketaryen"
        default: raw
        }
    }
}

enum CategoryLabel {
    static func turkish(_ raw: String) -> String {
        switch raw {
        case "main": "Ana yemek"
        case "soup": "Çorba"
        case "salad": "Salata"
        case "breakfast": "Kahvaltı"
        default: raw
        }
    }
}

enum RegionLabel {
    static func turkish(_ code: String) -> String {
        let locale = Locale(identifier: "tr_TR")
        return locale.localizedString(forRegionCode: code.uppercased()) ?? code
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

    /// Chip and picker label. Always a Turkish phrase, never a raw count or type dump.
    static func label(_ count: Int) -> String {
        let value = min(max(count, minimum), maximum)
        return "\(value) akşam"
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
        "\(minutes) dk"
    }
}
