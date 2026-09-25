import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecipeListViewModel {
    var searchText = ""
    var category: RecipeBrowseCategory = .all
    var cookTime: RecipeCookTimeFilter = .any
    var lovedOnly = false
    var errorMessage: String?

    @ObservationIgnored private var filteredKey: Int?
    @ObservationIgnored private var filteredRecipes: [Recipe] = []

    var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasChipFilters: Bool {
        category != .all || cookTime != .any || lovedOnly
    }

    var hasActiveFilters: Bool {
        hasChipFilters || hasSearchText
    }

    func clearFilters() {
        searchText = ""
        category = .all
        cookTime = .any
        lovedOnly = false
    }

    func filtered(_ recipes: [Recipe], ratings: [String: MealRating]) -> [Recipe] {
        let index = CatalogIndexCache.warm(recipes: recipes, ratings: ratings)
        let key = filterKey(indexKey: index.key, ratings: ratings)
        if key == filteredKey {
            return filteredRecipes
        }
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let proteinBySlug = Dictionary(index.candidates.map { ($0.slug, $0.protein) }, uniquingKeysWith: { first, _ in first })
        let items = recipes.map { recipe in
            RecipeBrowseItem(
                slug: recipe.slug,
                displayName: recipe.displayName,
                nameEN: recipe.nameEN,
                country: recipe.country,
                totalMinutes: recipe.totalMinutes,
                protein: proteinBySlug[recipe.slug] ?? "",
                diets: Set(recipe.diets.map { $0.lowercased() }),
                tags: Set(recipe.tags.map { $0.lowercased() }),
                isLoved: ratings[recipe.slug] == .loved
            )
        }
        let query = RecipeBrowseQuery(
            searchText: searchText,
            category: category,
            cookTime: cookTime,
            lovedOnly: lovedOnly
        )
        let visible = RecipeBrowse.filter(items, query: query).compactMap { bySlug[$0.slug] }
        filteredKey = key
        filteredRecipes = visible
        return visible
    }

    private func filterKey(indexKey: Int, ratings: [String: MealRating]) -> Int {
        var hasher = Hasher()
        hasher.combine(indexKey)
        hasher.combine(searchText)
        hasher.combine(category.rawValue)
        hasher.combine(cookTime.rawValue)
        hasher.combine(lovedOnly)
        for (slug, rating) in ratings.sorted(by: { $0.key < $1.key }) {
            hasher.combine(slug)
            hasher.combine(rating.rawValue)
        }
        return hasher.finalize()
    }

    func toggleFavorite(slug: String, isLoved: Bool, in context: ModelContext) {
        do {
            try WeekPlanService.setFavorite(slug: slug, loved: !isLoved, in: context)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
