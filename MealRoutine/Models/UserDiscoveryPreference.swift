import Foundation

/// How far the next plan leans toward meals the household already knows.
enum DiscoveryLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case familiar
    case balanced
    case adventurous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .familiar: "Tanıdık"
        case .balanced: "Dengeli"
        case .adventurous: "Meraklı"
        }
    }

    var detail: String {
        switch self {
        case .familiar: "Bildiğin yemekler önde gelsin"
        case .balanced: "Tanıdık ve yeni tarifler karışsın"
        case .adventurous: "Yeni kategori ve tariflere daha çok yer ver"
        }
    }
}

/// How soon a meal the household already cooks may return.
enum RepeatPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case occasionally
    case balanced
    case often

    var id: String { rawValue }

    var title: String {
        switch self {
        case .occasionally: "Ara sıra"
        case .balanced: "Dengeli"
        case .often: "Sık sık"
        }
    }

    var detail: String {
        switch self {
        case .occasionally: "Aynı tarifi daha seyrek gör"
        case .balanced: "Sevilenler kontrollü aralıkla dönsün"
        case .often: "Favoriler daha çabuk geri gelsin"
        }
    }

    /// Loved meals stay out for at least this many days. Often still respects a week.
    var lovedGapDays: Int {
        switch self {
        case .occasionally: 14
        case .balanced: 7
        case .often: 7
        }
    }
}

/// Difficulty gate for the next plan. Hard recipes stay out.
enum DifficultyPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case easyOnly
    case mostlyEasy
    case openToMedium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easyOnly: "Yalnızca kolay"
        case .mostlyEasy: "Çoğunlukla kolay"
        case .openToMedium: "Ortaya da açığım"
        }
    }

    var detail: String {
        switch self {
        case .easyOnly: "Yalnızca kolay tarifler"
        case .mostlyEasy: "Kolaylar önde, orta ara sıra"
        case .openToMedium: "Kolay ve orta tarifler"
        }
    }
}

/// Weekday slots (Monday–Friday) get this bias. The open week is left as it is.
enum WeekdayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case mostlyQuick
    case balanced
    case moreVariety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostlyQuick: "Çoğunlukla hızlı"
        case .balanced: "Dengeli"
        case .moreVariety: "Daha çeşitli"
        }
    }

    var detail: String {
        switch self {
        case .mostlyQuick: "Hafta içi daha kısa sürsün"
        case .balanced: "Süre ve çeşit birlikte"
        case .moreVariety: "Hafta içi mutfak ve protein değişsin"
        }
    }
}

/// Whether this household has already met the recipe.
enum DiscoveryStatus: String, Codable, Sendable {
    case unknown
    case new
    case familiar
    case explored
}

/// Shown only when there is enough personal history to tell the two apart.
enum FamiliarityBadge: String, Equatable, Sendable {
    case familiar
    case new

    var title: String {
        switch self {
        case .familiar: "Tanıdık"
        case .new: "Yeni"
        }
    }
}
