import Foundation
import SwiftData

/// Rebuilds the current week's shopping list from planned meals.
/// Each meal is scaled to its own `servings`, or to the household size when
/// that value is missing. Lines are then merged on ingredient id plus canonical unit.
/// Manual rows stay. A checked automatic row stays checked when the amount
/// on screen is unchanged, including when grams and kilograms are the same
/// mass. A changed amount clears the check. A hand-edited quantity is kept;
/// its check clears only when that displayed amount itself changes.
enum GroceryListService {
    @MainActor
    static func rebuild(in context: ModelContext, now: Date = .now) throws {
        guard let week = try WeekPlanService.currentWeek(in: context, now: now) else { return }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return }

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        var bySlug: [String: Recipe] = [:]
        for recipe in recipes {
            bySlug[recipe.slug] = recipe
        }
        var sources: [GrocerySourceLine] = []

        let householdSize = prefs.householdSize
        for meal in week.meals {
            guard let recipe = bySlug[meal.recipeSlug] else { continue }
            let servings = ActiveServings.resolve(
                mealServings: meal.servings,
                householdSize: householdSize
            )
            for ingredient in recipe.ingredients {
                let quantity = PortionScaler.scale(
                    quantity: ingredient.quantity,
                    scaling: ingredient.scaling,
                    baseServings: recipe.baseServings,
                    householdSize: servings
                )
                sources.append(
                    GrocerySourceLine(
                        ingredientId: ingredient.ingredientId,
                        nameTR: ingredient.displayName,
                        nameEN: ingredient.nameEN,
                        quantity: quantity,
                        unit: ingredient.unit
                    )
                )
            }
        }

        let merged = GroceryMerger.merge(sources)
        let autoItems = week.groceries.filter { !$0.isManual }
        let plan = GroceryListReconciler.plan(
            existingAuto: autoItems.map {
                AutoGroceryRow(
                    id: $0.uuid,
                    ingredientId: $0.ingredientId,
                    unit: $0.unit,
                    quantity: $0.quantity,
                    isChecked: $0.isChecked,
                    quantityIsCustom: $0.quantityIsCustom
                )
            },
            merged: merged
        )
        var byID: [UUID: GroceryItem] = [:]
        for item in autoItems {
            byID[item.uuid] = item
        }
        var didChange = false

        for update in plan.updates {
            guard let match = byID[update.existingID] else { continue }
            let line = merged[update.mergedIndex]
            let normalizedUnit = GroceryMerger.normalize(line.unit)
            let nextQuantity = GroceryQuantityEdit.quantityToStore(
                planned: line.quantity,
                edited: match.quantity,
                isCustom: match.quantityIsCustom
            )
            let nextUnit = match.quantityIsCustom ? match.unit : normalizedUnit
            let nextConflict = match.quantityIsCustom ? match.hasUnitConflict : line.hasUnitConflict
            let nextChecked = update.isChecked
            if match.nameTR != line.nameTR
                || match.nameEN != line.nameEN
                || match.quantity != nextQuantity
                || match.unit != nextUnit
                || match.hasUnitConflict != nextConflict
                || match.isChecked != nextChecked {
                match.nameTR = line.nameTR
                match.nameEN = line.nameEN
                match.quantity = nextQuantity
                match.unit = nextUnit
                match.hasUnitConflict = nextConflict
                match.isChecked = nextChecked
                didChange = true
            }
        }

        for index in plan.inserts {
            let line = merged[index]
            let item = GroceryItem(
                ingredientId: line.ingredientId,
                nameTR: line.nameTR,
                nameEN: line.nameEN,
                quantity: line.quantity,
                unit: GroceryMerger.normalize(line.unit),
                hasUnitConflict: line.hasUnitConflict,
                isChecked: false,
                isManual: false
            )
            context.insert(item)
            item.week = week
            didChange = true
        }

        for id in plan.deletes {
            if let item = byID[id] {
                context.delete(item)
                didChange = true
            }
        }
        if didChange {
            try context.save()
        }
    }

    @MainActor
    static func toggle(_ uuid: UUID, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        guard let item = items.first(where: { $0.uuid == uuid }) else { return }
        let wasChecked = item.isChecked
        item.isChecked.toggle()
        try context.save()
        guard item.isChecked, !wasChecked else { return }
        Analytics.track(.groceryItemChecked)
        if let week = item.week, !week.groceries.isEmpty, week.groceries.allSatisfy(\.isChecked) {
            Analytics.track(.groceryListCompleted)
        }
    }

    /// Writes a new amount and keeps the stored unit and aisle.
    /// A different amount clears the check so the new figure is visible.
    @MainActor
    static func updateQuantity(_ uuid: UUID, quantity: Double, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        guard let item = items.first(where: { $0.uuid == uuid }) else { return }
        item.isChecked = GroceryCheckState.checkedAfterQuantityEdit(
            wasChecked: item.isChecked,
            previousQuantity: item.quantity,
            unit: item.unit,
            editedQuantity: quantity
        )
        item.quantity = quantity
        item.quantityIsCustom = true
        try context.save()
    }

    @MainActor
    static func addManual(
        name: String,
        quantity: Double?,
        unit: String,
        in context: ModelContext,
        now: Date = .now
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let week = try WeekPlanService.currentWeek(in: context, now: now) else {
            throw WeekPlanError.missingPreferences
        }
        let item = GroceryItem(
            ingredientId: "manual:\(UUID().uuidString)",
            nameTR: trimmed,
            nameEN: trimmed,
            quantity: quantity,
            unit: GroceryMerger.normalize(unit),
            hasUnitConflict: false,
            isChecked: false,
            isManual: true
        )
        context.insert(item)
        item.week = week
        try context.save()
    }

    @MainActor
    static func deleteManual(_ uuid: UUID, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        guard let item = items.first(where: { $0.uuid == uuid && $0.isManual }) else { return }
        context.delete(item)
        try context.save()
    }
}
