import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileViewModel {
    var householdSize = 2
    var evenings = 5
    var maxCookMinutes = 60
    var dislikedIDs: [String] = []
    var didLoad = false
    var statusMessage: String?
    var errorMessage: String?

    func loadIfNeeded(_ prefs: UserPrefs?) {
        guard !didLoad, let prefs else { return }
        didLoad = true
        householdSize = prefs.householdSize
        evenings = prefs.eveningsPerWeek
        maxCookMinutes = prefs.maxCookMinutes
        dislikedIDs = prefs.dislikedIngredientIds
    }

    func dislikedNames(in recipes: [Recipe]) -> [String] {
        var names: [String: String] = [:]
        for recipe in recipes {
            for line in recipe.ingredients where names[line.ingredientId] == nil {
                names[line.ingredientId] = line.displayName
            }
        }
        return dislikedIDs.map { names[$0] ?? $0 }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func savePortions(in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            prefs.householdSize = householdSize
            prefs.eveningsPerWeek = min(max(evenings, 1), NaiveMealPicker.eveningCap)
            prefs.maxCookMinutes = maxCookMinutes
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
            prefs.householdSize = householdSize
            prefs.eveningsPerWeek = min(max(evenings, 1), NaiveMealPicker.eveningCap)
            prefs.maxCookMinutes = maxCookMinutes
            try context.save()
            let request = PlanRequest(
                householdSize: prefs.householdSize,
                evenings: prefs.eveningsPerWeek,
                maxCookMinutes: prefs.maxCookMinutes,
                dislikedIngredientIds: Set(prefs.dislikedIngredientIds)
            )
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
