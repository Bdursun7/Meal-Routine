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
    var isConfirmingReset = false
    /// Last values read from the store. An untouched stepper adopts a save made elsewhere.
    private var loadedHousehold = 2
    private var loadedEvenings = 5
    private var loadedMinutes = CookTimeOptions.defaultMinutes
    private var loadedDislikes: [String] = []

    /// Refreshes the form from the store. A stepper the user has moved, and not saved, is left alone.
    func load(_ prefs: UserPrefs?) {
        guard let prefs else { return }
        let storedHousehold = HouseholdSizeLimits.clamped(prefs.householdSize)
        let storedEvenings = min(max(prefs.eveningsPerWeek, 1), MealRecommender.eveningCap)
        let storedMinutes = CookTimeOptions.resolved(prefs.maxCookMinutes)
        let storedDislikes = prefs.dislikedIngredientIds
        if !didLoad || householdSize == loadedHousehold {
            householdSize = storedHousehold
        }
        if !didLoad || evenings == loadedEvenings {
            evenings = storedEvenings
        }
        if !didLoad || maxCookMinutes == loadedMinutes {
            maxCookMinutes = storedMinutes
        }
        if !didLoad || dislikedIDs == loadedDislikes {
            dislikedIDs = storedDislikes
        }
        loadedHousehold = storedHousehold
        loadedEvenings = storedEvenings
        loadedMinutes = storedMinutes
        loadedDislikes = storedDislikes
        didLoad = true
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
            prefs.eveningsPerWeek = min(max(evenings, 1), MealRecommender.eveningCap)
            prefs.maxCookMinutes = CookTimeOptions.resolved(maxCookMinutes)
            try PortionSaveService.saveHouseholdSize(householdSize, in: context)
            householdSize = HouseholdSizeLimits.clamped(prefs.householdSize)
            evenings = min(max(prefs.eveningsPerWeek, 1), MealRecommender.eveningCap)
            maxCookMinutes = CookTimeOptions.resolved(prefs.maxCookMinutes)
            loadedHousehold = householdSize
            loadedEvenings = evenings
            loadedMinutes = maxCookMinutes
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
            loadedHousehold = householdSize
            loadedEvenings = evenings
            loadedMinutes = maxCookMinutes
            try context.save()
            let request = WeekPlanService.planRequest(from: prefs)
            _ = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            try GroceryListService.rebuild(in: context)
            statusMessage = "Bu hafta yeniden kuruldu."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes household prefs, the week, the grocery list, ratings, and the exposure log.
    /// The bundled recipe catalog stays on device.
    func resetLocalData(in context: ModelContext) {
        do {
            let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
            let items = try context.fetch(FetchDescriptor<GroceryItem>())
            let orphanMeals = meals.filter { $0.week == nil }
            let orphanItems = items.filter { $0.week == nil }
            let weeks = try context.fetch(FetchDescriptor<PlanWeek>())
            for week in weeks { context.delete(week) }
            for meal in orphanMeals { context.delete(meal) }
            for item in orphanItems { context.delete(item) }
            let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
            for entry in feedback { context.delete(entry) }
            let storedPrefs = try context.fetch(FetchDescriptor<UserPrefs>())
            for prefs in storedPrefs { context.delete(prefs) }
            try context.save()
            UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
            didLoad = false
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
