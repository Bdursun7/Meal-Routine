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
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let items = recipes.map { recipe in
            RecipeBrowseItem(
                slug: recipe.slug,
                displayName: recipe.displayName,
                nameEN: recipe.nameEN,
                country: recipe.country,
                totalMinutes: recipe.totalMinutes,
                protein: MealRecommender.proteinFamily(in: Self.orderedIDs(recipe)),
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
        return RecipeBrowse.filter(items, query: query).compactMap { bySlug[$0.slug] }
    }

    func toggleFavorite(slug: String, isLoved: Bool, in context: ModelContext) {
        do {
            try WeekPlanService.setFavorite(slug: slug, loved: !isLoved, in: context)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func orderedIDs(_ recipe: Recipe) -> [String] {
        recipe.ingredients
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.ingredientId < rhs.ingredientId
            }
            .map(\.ingredientId)
    }
}
