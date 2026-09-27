import Foundation
import Observation
import SwiftData

struct MealMemorySummary: Equatable {
    var favoriteNames: [String]
    var mostCooked: [String]
    var recentLoved: [String]
    var patterns: [MealPattern]
    var neverAgain: [String]
    var avoidedIngredients: [String]
    var timeConcerns: [String]
    var explored: [String]
    var firstCategories: [String]
    var hasHistory: Bool
}

@MainActor
@Observable
final class MealMemoryViewModel {
    var isConfirmingReset = false
    var errorMessage: String?
    var statusMessage: String?

    func summary(
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        memories: [MealMemory],
        prefs: UserPrefs?
    ) -> MealMemorySummary {
        let names = Dictionary(recipes.map { ($0.slug, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let index = CatalogIndexCache.warm(
            recipes: recipes,
            ratings: FeedbackIndex.latestRatings(in: feedback)
        )
        let bySlug = index.bySlug
        let snapshots = memories.map(\.snapshot)
        let map = Dictionary(snapshots.map { ($0.recipeID, $0) }, uniquingKeysWith: { first, _ in first })
        func label(_ slug: String) -> String { names[slug] ?? slug }

        let favorites = snapshots
            .filter { $0.isFavorite || $0.lovedCount > 0 }
            .sorted { lhs, rhs in
                if lhs.lovedCount != rhs.lovedCount { return lhs.lovedCount > rhs.lovedCount }
                return label(lhs.recipeID).localizedStandardCompare(label(rhs.recipeID)) == .orderedAscending
            }
            .prefix(5)
            .map { label($0.recipeID) }

        let cooked = snapshots
            .filter { $0.timesCooked > 0 }
            .sorted { lhs, rhs in
                if lhs.timesCooked != rhs.timesCooked { return lhs.timesCooked > rhs.timesCooked }
                return label(lhs.recipeID).localizedStandardCompare(label(rhs.recipeID)) == .orderedAscending
            }
            .prefix(5)
            .map { "\(label($0.recipeID)) · \($0.timesCooked) kez" }

        let recent = snapshots
            .filter { $0.lovedCount > 0 }
            .sorted { lhs, rhs in
                let left = lhs.lastCookedAt ?? .distantPast
                let right = rhs.lastCookedAt ?? .distantPast
                if left != right { return left > right }
                return label(lhs.recipeID).localizedStandardCompare(label(rhs.recipeID)) == .orderedAscending
            }
            .prefix(5)
            .map { label($0.recipeID) }

        let never = snapshots
            .filter(\.neverAgain)
            .map { label($0.recipeID) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let slow = snapshots
            .filter { $0.timeConcernCount > 0 }
            .map { label($0.recipeID) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        let explored = snapshots
            .filter { $0.discoveryStatus == .explored }
            .map { label($0.recipeID) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var seenCategories: Set<String> = []
        var firstCategories: [String] = []
        for snapshot in snapshots where snapshot.discoveryStatus == .explored || snapshot.timesCooked > 0 {
            guard let category = bySlug[snapshot.recipeID]?.category, !category.isEmpty else { continue }
            let key = category.lowercased()
            if seenCategories.insert(key).inserted, snapshot.timesCooked <= 2 {
                firstCategories.append(CategoryLabel.turkish(category))
            }
        }

        let disliked = prefs?.dislikedIngredientIds ?? []
        let avoided = disliked.map { index.ingredientNames[$0] ?? $0 }

        let patterns = MealPatternService.patterns(
            memories: map,
            bySlug: bySlug,
            dismissed: Set(prefs?.dismissedPatternIDs ?? [])
        )
        let points = MealMemoryReducer.dataPointCount(in: snapshots)
        return MealMemorySummary(
            favoriteNames: Array(favorites),
            mostCooked: Array(cooked),
            recentLoved: Array(recent),
            patterns: patterns,
            neverAgain: never,
            avoidedIngredients: avoided,
            timeConcerns: slow,
            explored: explored,
            firstCategories: Array(firstCategories.prefix(6)),
            hasHistory: points > 0 || !favorites.isEmpty
        )
    }

    func dismiss(_ patternID: String, in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            if !prefs.dismissedPatternIDs.contains(patternID) {
                prefs.dismissedPatternIDs.append(patternID)
            }
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset(in context: ModelContext) {
        do {
            try MealMemoryService.reset(in: context)
            statusMessage = "Yemek hafızası silindi. Kurulum tercihlerin duruyor."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
