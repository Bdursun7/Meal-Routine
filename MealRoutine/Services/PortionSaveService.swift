import Foundation
import SwiftData

enum PortionSaveError: LocalizedError {
    case missingMeal

    var errorDescription: String? {
        switch self {
        case .missingMeal:
            "Bu akşam artık planda yok."
        }
    }
}

/// Writes the serving count that recipe detail and `GroceryListService` both read.
enum PortionSaveService {
    /// Locks the household default and copies it onto every evening of the open week.
    ///
    /// A per-meal override is replaced on purpose: changing the household from
    /// Profile, or from a recipe that is not tied to one evening, moves the
    /// whole week together. Grocery rows are rebuilt in place.
    @MainActor
    static func saveHouseholdSize(_ size: Int, in context: ModelContext, now: Date = .now) throws {
        guard let prefs = try UserPrefsStore.existing(in: context) else {
            throw WeekPlanError.missingPreferences
        }
        let clamped = HouseholdSizeLimits.clamped(size)
        prefs.householdSize = clamped
        if let week = try WeekPlanService.currentWeek(in: context, now: now) {
            week.householdSize = clamped
            for meal in week.meals {
                meal.servings = clamped
            }
        }
        try context.save()
        try GroceryListService.rebuild(in: context, now: now)
    }

    /// Saves one evening. Other evenings and `UserPrefs.householdSize` stay as they are.
    @MainActor
    static func saveMealServings(
        _ servings: Int,
        mealUUID: UUID,
        in context: ModelContext,
        now: Date = .now
    ) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == mealUUID }) else {
            throw PortionSaveError.missingMeal
        }
        meal.servings = HouseholdSizeLimits.clamped(servings)
        try context.save()
        try GroceryListService.rebuild(in: context, now: now)
    }
}
