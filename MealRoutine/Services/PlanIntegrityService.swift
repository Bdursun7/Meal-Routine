import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.mealroutine.app", category: "plan")

/// Drops planned meals whose recipe disappeared, then leaves grocery rebuild to the caller.
///
/// Current-week orphans are replaced by `WeekPlanService.replaceCurrentWeek` (naive picker)
/// when onboarding is done. A hole-only delete would keep grocery math "correct" for the
/// meals that remain, but the week would no longer match the household's evening count.
/// Replacing the week deletes that week's grocery rows; manual extras are copied onto the
/// new week first. Checked auto-rows reset with the new list, then `GroceryListService.rebuild`
/// fills it from the new meals.
/// Older weeks only lose orphan meals. Their history is not regenerated.
enum PlanIntegrityService {
    @MainActor
    static func repair(in context: ModelContext, now: Date = .now) throws -> Bool {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let live = Set(recipes.map(\.slug))
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let currentWeek = try WeekPlanService.currentWeek(in: context, now: now)
        let currentID = currentWeek?.uuid

        let currentMealIDs = Set(currentWeek?.meals.map(\.uuid) ?? [])
        var currentSlugs: [String] = []
        var otherSlugs: [String] = []
        for meal in meals {
            let isCurrent = currentID != nil
                && (meal.week?.uuid == currentID || currentMealIDs.contains(meal.uuid))
            if isCurrent {
                currentSlugs.append(meal.recipeSlug)
            } else {
                otherSlugs.append(meal.recipeSlug)
            }
        }

        let canRegenerate = try canRegenerateCurrentWeek(in: context)
        let decision = PlanRepair.decide(
            currentWeekSlugs: currentSlugs,
            otherWeekSlugs: otherSlugs,
            liveRecipeSlugs: live,
            canRegenerateCurrentWeek: canRegenerate
        )
        guard decision.regenerateCurrentWeek || !decision.slugsToDelete.isEmpty else {
            return false
        }

        if decision.regenerateCurrentWeek, let prefs = try UserPrefsStore.existing(in: context) {
            let manuals = manualSnapshots(from: currentWeek)
            let week = try WeekPlanService.replaceCurrentWeek(
                in: context,
                request: WeekPlanService.planRequest(from: prefs),
                now: now
            )
            try deleteMeals(withSlugs: Set(decision.slugsToDelete), in: context)
            restore(manuals, onto: week, in: context)
            try context.save()
            logger.info("Regenerated the current week after orphaned recipe slugs")
            return true
        }

        // Regeneration needs finished onboarding. Without it, delete every orphan
        // in place, including the current week (decide() would have kept those
        // slugs out of slugsToDelete because it expected a regenerate).
        let slugsToDelete = decision.regenerateCurrentWeek
            ? PlanRepair.orphanedSlugs(
                plannedSlugs: currentSlugs + otherSlugs,
                liveRecipeSlugs: live
            )
            : decision.slugsToDelete
        try deleteMeals(withSlugs: Set(slugsToDelete), in: context)
        try context.save()
        logger.info("Removed planned meals whose recipes are no longer in the catalog")
        return true
    }

    @MainActor
    private static func canRegenerateCurrentWeek(in context: ModelContext) throws -> Bool {
        guard let prefs = try UserPrefsStore.existing(in: context) else { return false }
        return prefs.hasCompletedOnboarding
    }

    @MainActor
    private static func deleteMeals(withSlugs slugs: Set<String>, in context: ModelContext) throws {
        guard !slugs.isEmpty else { return }
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        for meal in meals where slugs.contains(meal.recipeSlug) {
            context.delete(meal)
        }
    }

    private static func manualSnapshots(from week: PlanWeek?) -> [ManualGrocerySnapshot] {
        guard let week else { return [] }
        return week.groceries.filter(\.isManual).map { item in
            ManualGrocerySnapshot(
                ingredientId: item.ingredientId,
                nameTR: item.nameTR,
                nameEN: item.nameEN,
                quantity: item.quantity,
                unit: item.unit,
                hasUnitConflict: item.hasUnitConflict,
                isChecked: item.isChecked
            )
        }
    }

    @MainActor
    private static func restore(
        _ manuals: [ManualGrocerySnapshot],
        onto week: PlanWeek,
        in context: ModelContext
    ) {
        for manual in manuals {
            let item = GroceryItem(
                ingredientId: manual.ingredientId,
                nameTR: manual.nameTR,
                nameEN: manual.nameEN,
                quantity: manual.quantity,
                unit: manual.unit,
                hasUnitConflict: manual.hasUnitConflict,
                isChecked: manual.isChecked,
                isManual: true
            )
            context.insert(item)
            item.week = week
        }
    }
}

private struct ManualGrocerySnapshot {
    var ingredientId: String
    var nameTR: String
    var nameEN: String
    var quantity: Double?
    var unit: String
    var hasUnitConflict: Bool
    var isChecked: Bool
}
