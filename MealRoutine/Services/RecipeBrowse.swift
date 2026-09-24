import Foundation

/// Category chips on Tarifler. Labels are Turkish. Matching uses protein, diet, and tags
/// already stored on the catalog — the list is not rebuilt.
enum RecipeBrowseCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case chicken
    case beef
    case fish
    case vegetarian
    case pasta
    case rice
    case quick
    case oven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .chicken: "Tavuk"
        case .beef: "Kırmızı et"
        case .fish: "Balık"
        case .vegetarian: "Vejetaryen"
        case .pasta: "Makarna"
        case .rice: "Pirinç"
        case .quick: "Hızlı"
        case .oven: "Fırın"
        }
    }
}

/// Upper bound on total minutes. `any` leaves the catalog's own times alone.
enum RecipeCookTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case upTo30
    case upTo45
    case upTo60
    case upTo90

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Hepsi"
        case .upTo30: "30 dk"
        case .upTo45: "45 dk"
        case .upTo60: "60 dk"
        case .upTo90: "90 dk"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .any: "Süre sınırı yok"
        case .upTo30: "En fazla 30 dakika"
        case .upTo45: "En fazla 45 dakika"
        case .upTo60: "En fazla 60 dakika"
        case .upTo90: "En fazla 90 dakika"
        }
    }

    var maxMinutes: Int? {
        switch self {
        case .any: nil
        case .upTo30: 30
        case .upTo45: 45
        case .upTo60: 60
        case .upTo90: 90
        }
    }
}

struct RecipeBrowseQuery: Equatable, Sendable {
    var searchText = ""
    var category: RecipeBrowseCategory = .all
    var cookTime: RecipeCookTimeFilter = .any
    var lovedOnly = false
}

/// Fields the list can filter without a SwiftData model.
struct RecipeBrowseItem: Equatable, Sendable {
    var slug: String
    var displayName: String
    var nameEN: String
    var country: String
    var totalMinutes: Int
    var protein: String
    var diets: Set<String>
    var tags: Set<String>
    var isLoved: Bool
}

enum RecipeBrowse {
    static func filter(_ items: [RecipeBrowseItem], query: RecipeBrowseQuery) -> [RecipeBrowseItem] {
        let text = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items
            .filter { item in
                matchesCategory(item, query.category)
                    && matchesTime(item, query.cookTime)
                    && (!query.lovedOnly || item.isLoved)
                    && matchesSearch(item, text)
            }
            .sorted { lhs, rhs in
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.slug < rhs.slug
            }
    }

    static func matchesCategory(_ item: RecipeBrowseItem, _ category: RecipeBrowseCategory) -> Bool {
        switch category {
        case .all:
            return true
        case .chicken:
            return item.protein == "poultry"
        case .beef:
            return item.protein == "red-meat"
        case .fish:
            return item.protein == "seafood"
        case .vegetarian:
            return item.diets.contains("vegetarian") || item.diets.contains("vegan")
        case .pasta:
            return item.tags.contains("pasta")
        case .rice:
            return item.tags.contains("rice")
        case .quick:
            return item.tags.contains("quick") || item.totalMinutes <= 30
        case .oven:
            return item.tags.contains("bake")
        }
    }

    private static func matchesTime(_ item: RecipeBrowseItem, _ filter: RecipeCookTimeFilter) -> Bool {
        guard let maxMinutes = filter.maxMinutes else { return true }
        return item.totalMinutes <= maxMinutes
    }

    private static func matchesSearch(_ item: RecipeBrowseItem, _ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        return item.displayName.localizedCaseInsensitiveContains(text)
            || item.nameEN.localizedCaseInsensitiveContains(text)
            || item.country.localizedCaseInsensitiveContains(text)
    }
}
