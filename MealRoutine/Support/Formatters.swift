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
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        // Two places so a summed 1.25 kg is not rounded to the nearest tenth.
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
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
