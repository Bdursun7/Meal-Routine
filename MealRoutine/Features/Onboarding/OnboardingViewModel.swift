import Foundation
import Observation
import SwiftData

struct IngredientChip: Identifiable, Equatable {
    var id: String
    var name: String
}

/// Collects household prefs and an optional Loved / Okay / Never sample.
@MainActor
@Observable
final class OnboardingViewModel {
    var step = 0
    var householdSize = 2
    var evenings = 5
    var maxCookMinutes = 60
    var disliked: Set<String> = []
    var ratings: [String: MealRating] = [:]
    var chips: [IngredientChip] = []
    var isSaving = false
    var errorMessage: String?

    /// Staples that are poor "dislike" chips for a first-run stub.
    private let pantryIDs: Set<String> = [
        "salt", "oil", "pepper", "water", "blackpepper", "black-pepper"
    ]

    func loadChips(from recipes: [Recipe]) {
        guard chips.isEmpty, !recipes.isEmpty else { return }

        struct Tally {
            var name: String
            var count: Int
        }

        var tallies: [String: Tally] = [:]
        for recipe in recipes {
            var seen: Set<String> = []
            for line in recipe.ingredients where seen.insert(line.ingredientId).inserted {
                guard !pantryIDs.contains(line.ingredientId) else { continue }
                var tally = tallies[line.ingredientId] ?? Tally(name: line.displayName, count: 0)
                tally.count += 1
                if tally.name.isEmpty { tally.name = line.displayName }
                tallies[line.ingredientId] = tally
            }
        }

        chips = tallies
            .map { IngredientChip(id: $0.key, name: $0.value.name) }
            .sorted { lhs, rhs in
                let left = tallies[lhs.id]?.count ?? 0
                let right = tallies[rhs.id]?.count ?? 0
                if left != right { return left > right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(24)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func sampleRecipes(from recipes: [Recipe]) -> [Recipe] {
        recipes
            .sorted { lhs, rhs in
                if lhs.trDogfoodScore != rhs.trDogfoodScore {
                    return lhs.trDogfoodScore > rhs.trDogfoodScore
                }
                return lhs.slug < rhs.slug
            }
            .prefix(20)
            .map { $0 }
    }

    func toggleDislike(_ id: String) {
        if disliked.contains(id) {
            disliked.remove(id)
        } else {
            disliked.insert(id)
        }
    }

    func finish(in context: ModelContext) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let prefs: UserPrefs
            if let existing = try UserPrefsStore.existing(in: context) {
                prefs = existing
            } else {
                prefs = UserPrefs()
                context.insert(prefs)
            }
            prefs.householdSize = householdSize
            prefs.eveningsPerWeek = min(max(evenings, 1), NaiveMealPicker.eveningCap)
            prefs.maxCookMinutes = maxCookMinutes
            prefs.dislikedIngredientIds = disliked.sorted()
            prefs.hasCompletedOnboarding = false

            for (slug, rating) in ratings {
                context.insert(RecipeFeedback(recipeSlug: slug, rating: rating, cooked: false))
            }
            try context.save()

            let request = PlanRequest(
                householdSize: prefs.householdSize,
                evenings: prefs.eveningsPerWeek,
                maxCookMinutes: prefs.maxCookMinutes,
                dislikedIngredientIds: Set(prefs.dislikedIngredientIds)
            )
            _ = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            try GroceryListService.rebuild(in: context)
            prefs.hasCompletedOnboarding = true
            try context.save()
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
