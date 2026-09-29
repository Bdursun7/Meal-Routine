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
    var library: RecipeLibraryScope = .all
    var sort: RecipeLibrarySort = .alphabetical
    var errorMessage: String?

    @ObservationIgnored private var filteredKey: Int?
    @ObservationIgnored private var filteredRecipes: [Recipe] = []

    var hasSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasChipFilters: Bool {
        category != .all || cookTime != .any || lovedOnly || library != .all
    }

    var hasActiveFilters: Bool {
        hasChipFilters || hasSearchText
    }

    func clearFilters() {
        searchText = ""
        category = .all
        cookTime = .any
        lovedOnly = false
        library = .all
        sort = .alphabetical
    }

    func filtered(
        _ recipes: [Recipe],
        ratings: [String: MealRating],
        memories: [MealMemory] = []
    ) -> [Recipe] {
        let index = CatalogIndexCache.warm(recipes: recipes, ratings: ratings)
        let key = filterKey(indexKey: index.key, ratings: ratings, memories: memories)
        if key == filteredKey {
            return filteredRecipes
        }
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let proteinBySlug = Dictionary(index.candidates.map { ($0.slug, $0.protein) }, uniquingKeysWith: { first, _ in first })
        let memoryBySlug = Dictionary(memories.map { ($0.recipeSlug, $0) }, uniquingKeysWith: { first, _ in first })
        let items: [RecipeBrowseItem] = recipes.map { recipe in
            let memory = memoryBySlug[recipe.slug]
            return RecipeBrowseItem(
                slug: recipe.slug,
                displayName: recipe.displayName,
                nameEN: recipe.nameEN,
                country: recipe.country,
                totalMinutes: recipe.timeIsUnknown ? 10_000 : recipe.totalMinutes,
                protein: proteinBySlug[recipe.slug] ?? "",
                diets: Set(recipe.diets.map { $0.lowercased() }),
                tags: Set(recipe.tags.map { $0.lowercased() }),
                isLoved: ratings[recipe.slug] == .loved || memory?.isFavorite == true,
                origin: recipe.originRaw,
                requiresReview: recipe.requiresReview,
                importedAt: recipe.importedAt,
                lastCookedAt: memory?.lastCookedAt,
                timesCooked: memory?.timesCooked ?? 0,
                searchBlob: index.searchBlobs[recipe.slug] ?? ""
            )
        }
        let query = RecipeBrowseQuery(
            searchText: searchText,
            category: category,
            cookTime: cookTime,
            lovedOnly: lovedOnly,
            library: library,
            sort: sort
        )
        let visible = RecipeBrowse.filter(items, query: query).compactMap { bySlug[$0.slug] }
        filteredKey = key
        filteredRecipes = visible
        return visible
    }

    private func filterKey(indexKey: Int, ratings: [String: MealRating], memories: [MealMemory]) -> Int {
        var hasher = Hasher()
        hasher.combine(indexKey)
        hasher.combine(searchText)
        hasher.combine(category.rawValue)
        hasher.combine(cookTime.rawValue)
        hasher.combine(lovedOnly)
        hasher.combine(library.rawValue)
        hasher.combine(sort.rawValue)
        for (slug, rating) in ratings.sorted(by: { $0.key < $1.key }) {
            hasher.combine(slug)
            hasher.combine(rating.rawValue)
        }
        for memory in memories.sorted(by: { $0.recipeSlug < $1.recipeSlug }) {
            hasher.combine(memory.recipeSlug)
            hasher.combine(memory.timesCooked)
            hasher.combine(memory.isFavorite)
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
