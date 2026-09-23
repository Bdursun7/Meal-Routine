import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileViewModel {
    var householdSize = 2
    var evenings = 5
    var maxCookMinutes = CookTimeOptions.defaultMinutes
    var dislikedIDs: [String] = []
    var didLoad = false
    var statusMessage: String?
    var errorMessage: String?

    func loadIfNeeded(_ prefs: UserPrefs?) {
        guard !didLoad, let prefs else { return }
        didLoad = true
        householdSize = HouseholdSizeLimits.clamped(prefs.householdSize)
        evenings = min(max(prefs.eveningsPerWeek, 1), MealRecommender.eveningCap)
        maxCookMinutes = CookTimeOptions.resolved(prefs.maxCookMinutes)
        dislikedIDs = prefs.dislikedIngredientIds
    }

    func dislikedNames(in recipes: [Recipe]) -> [String] {
        var names: [String: String] = [:]
        for recipe in recipes {
            for line in recipe.ingredients where names[line.ingredientId] == nil {
                if let group = DislikeChipMerge.group(containing: line.ingredientId) {
                    names[line.ingredientId] = group.name
                } else {
                    names[line.ingredientId] = line.displayName
                }
            }
        }
        var seen: Set<String> = []
        var labels: [String] = []
        for id in dislikedIDs {
            let label = names[id] ?? DislikeChipMerge.group(containing: id)?.name ?? id
            if seen.insert(label).inserted {
                labels.append(label)
            }
        }
        return labels.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func savePortions(in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            prefs.householdSize = HouseholdSizeLimits.clamped(householdSize)
            prefs.eveningsPerWeek = min(max(evenings, 1), MealRecommender.eveningCap)
            prefs.maxCookMinutes = CookTimeOptions.resolved(maxCookMinutes)
            householdSize = prefs.householdSize
            evenings = prefs.eveningsPerWeek
            maxCookMinutes = prefs.maxCookMinutes
            if let week = try WeekPlanService.currentWeek(in: context) {
                week.householdSize = prefs.householdSize
                for meal in week.meals {
                    meal.servings = prefs.householdSize
                }
            }
            try context.save()
            try GroceryListService.rebuild(in: context)
            statusMessage = "Porsiyon ve market listesi güncellendi."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildWeek(in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            prefs.householdSize = HouseholdSizeLimits.clamped(householdSize)
            prefs.eveningsPerWeek = min(max(evenings, 1), MealRecommender.eveningCap)
            prefs.maxCookMinutes = CookTimeOptions.resolved(maxCookMinutes)
            householdSize = prefs.householdSize
            evenings = prefs.eveningsPerWeek
            maxCookMinutes = prefs.maxCookMinutes
            try context.save()
            let request = WeekPlanService.planRequest(from: prefs)
            _ = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            try GroceryListService.rebuild(in: context)
            statusMessage = "Bu hafta yeniden kuruldu."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reopenOnboarding(in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            prefs.hasCompletedOnboarding = false
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
