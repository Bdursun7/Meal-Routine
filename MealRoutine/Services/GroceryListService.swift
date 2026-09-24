import Foundation
import SwiftData

/// Rebuilds the current week's shopping list from planned meals.
/// Each meal is scaled to its own `servings`, or to the household size when
/// that value is missing. Lines are then merged on ingredient id plus canonical unit.
/// Manual rows stay. A checked automatic row stays checked when the amount
/// on screen is unchanged, including when grams and kilograms are the same
/// mass. A changed amount clears the check. A hand-edited quantity is kept;
/// its check clears only when that displayed amount itself changes.
///
/// Ingredient checks on a planned meal cover their own scaled quantity.
/// A merged row is fully checked only when those contributions reach the
/// amount on the row. A partial cover leaves the row unchecked and stores
/// the remainder in `uncoveredQuantity`.
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

        let householdSize = prefs.householdSize
        var sources: [GrocerySourceLine] = []
        var contributions: [GroceryContribution] = []
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
                contributions.append(
                    GroceryContribution(
                        mealUUID: meal.uuid,
                        recipeSlug: meal.recipeSlug,
                        sortIndex: ingredient.sortIndex,
                        ingredientId: ingredient.ingredientId,
                        quantity: quantity,
                        unit: ingredient.unit
                    )
                )
            }
        }

        let mealIDs = Set(week.meals.map(\.uuid))
        _ = try reconcileStoredChecks(contributions: contributions, weekMealIDs: mealIDs, in: context)
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>()).map(record(from:))

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
            let resolution = resolution(
                legacyKeepsCheck: update.isChecked,
                requiredQuantity: nextQuantity,
                requiredUnit: nextUnit,
                ingredientId: line.ingredientId,
                contributions: contributions,
                checks: checks
            )
            if match.nameTR != line.nameTR
                || match.nameEN != line.nameEN
                || match.quantity != nextQuantity
                || match.unit != nextUnit
                || match.hasUnitConflict != nextConflict
                || match.isChecked != resolution.isChecked
                || match.uncoveredQuantity != resolution.uncoveredQuantity {
                match.nameTR = line.nameTR
                match.nameEN = line.nameEN
                match.quantity = nextQuantity
                match.unit = nextUnit
                match.hasUnitConflict = nextConflict
                match.isChecked = resolution.isChecked
                match.uncoveredQuantity = resolution.uncoveredQuantity
                didChange = true
            }
        }

        for index in plan.inserts {
            let line = merged[index]
            let unit = GroceryMerger.normalize(line.unit)
            let resolution = resolution(
                legacyKeepsCheck: false,
                requiredQuantity: line.quantity,
                requiredUnit: unit,
                ingredientId: line.ingredientId,
                contributions: contributions,
                checks: checks
            )
            let item = GroceryItem(
                ingredientId: line.ingredientId,
                nameTR: line.nameTR,
                nameEN: line.nameEN,
                quantity: line.quantity,
                unit: unit,
                hasUnitConflict: line.hasUnitConflict,
                isChecked: resolution.isChecked,
                isManual: false
            )
            item.uncoveredQuantity = resolution.uncoveredQuantity
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
        let turningOn = !item.isChecked
        if item.isManual {
            item.isChecked = turningOn
            try context.save()
        } else {
            try setContributionChecks(matching: item, checked: turningOn, in: context)
            item.isChecked = turningOn
            item.uncoveredQuantity = nil
            try context.save()
            try rebuild(in: context)
        }
        guard item.isChecked, turningOn else { return }
        Analytics.track(.groceryItemChecked)
        if let week = item.week, !week.groceries.isEmpty, week.groceries.allSatisfy(\.isChecked) {
            Analytics.track(.groceryListCompleted)
        }
    }

    /// Writes a new amount and keeps the stored unit and aisle.
    /// A different amount clears the check so the new figure is visible.
    /// The next rebuild then recalculates how much of that displayed amount the recipe checks still cover.
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
        item.uncoveredQuantity = nil
        try context.save()
        if !item.isManual {
            try rebuild(in: context)
        }
    }

    /// Persists one ingredient check. Planned meals also rebuild Market.
    @MainActor
    static func setIngredientCheck(
        mealUUID: UUID?,
        recipeSlug: String,
        ingredientId: String,
        sortIndex: Int,
        isChecked: Bool,
        quantity: Double?,
        unit: String,
        in context: ModelContext
    ) throws {
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        let match = checks.first { check in
            check.mealUUID == mealUUID
                && check.recipeSlug == recipeSlug
                && check.ingredientId == ingredientId
                && check.sortIndex == sortIndex
        }
        let storedUnit = GroceryMerger.normalize(unit)
        if let match {
            match.isChecked = isChecked
            match.coveredQuantity = quantity
            match.unit = storedUnit
        } else {
            let created = IngredientCheck(
                mealUUID: mealUUID,
                recipeSlug: recipeSlug,
                ingredientId: ingredientId,
                sortIndex: sortIndex,
                isChecked: isChecked,
                coveredQuantity: quantity,
                unit: storedUnit
            )
            context.insert(created)
        }
        try context.save()
        if mealUUID != nil {
            try rebuild(in: context)
        }
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

    /// Drops checks for meals no longer on this week, and clears a check whose scaled amount moved.
    @MainActor
    static func reconcileStoredChecks(
        contributions: [GroceryContribution],
        weekMealIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> Bool {
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        var didChange = false
        for check in checks {
            guard let mealUUID = check.mealUUID else { continue }
            guard weekMealIDs.contains(mealUUID) else {
                context.delete(check)
                didChange = true
                continue
            }
            guard let contribution = contributions.first(where: {
                $0.mealUUID == mealUUID
                    && $0.sortIndex == check.sortIndex
                    && $0.ingredientId == check.ingredientId
            }) else {
                context.delete(check)
                didChange = true
                continue
            }
            if check.isChecked, !GroceryCoverage.stillCovers(
                isChecked: true,
                coveredQuantity: check.coveredQuantity,
                coveredUnit: check.unit,
                quantity: contribution.quantity,
                unit: contribution.unit
            ) {
                check.isChecked = false
                didChange = true
            }
        }
        if didChange {
            try context.save()
        }
        return didChange
    }

    @MainActor
    private static func setContributionChecks(
        matching item: GroceryItem,
        checked: Bool,
        in context: ModelContext
    ) throws {
        guard let week = try item.week ?? WeekPlanService.currentWeek(in: context) else { return }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return }
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        var bySlug: [String: Recipe] = [:]
        for recipe in recipes {
            bySlug[recipe.slug] = recipe
        }
        let identity = GroceryMerger.rowIdentity(ingredientId: item.ingredientId, unit: item.unit)
        var contributions: [GroceryContribution] = []
        for meal in week.meals {
            guard let recipe = bySlug[meal.recipeSlug] else { continue }
            let servings = ActiveServings.resolve(
                mealServings: meal.servings,
                householdSize: prefs.householdSize
            )
            for ingredient in recipe.ingredients {
                let quantity = PortionScaler.scale(
                    quantity: ingredient.quantity,
                    scaling: ingredient.scaling,
                    baseServings: recipe.baseServings,
                    householdSize: servings
                )
                guard GroceryMerger.rowIdentity(ingredientId: ingredient.ingredientId, unit: ingredient.unit) == identity else {
                    continue
                }
                contributions.append(
                    GroceryContribution(
                        mealUUID: meal.uuid,
                        recipeSlug: meal.recipeSlug,
                        sortIndex: ingredient.sortIndex,
                        ingredientId: ingredient.ingredientId,
                        quantity: quantity,
                        unit: ingredient.unit
                    )
                )
            }
        }
        let existing = try context.fetch(FetchDescriptor<IngredientCheck>())
        for contribution in contributions {
            let match = existing.first { check in
                check.mealUUID == contribution.mealUUID
                    && check.sortIndex == contribution.sortIndex
                    && check.ingredientId == contribution.ingredientId
            }
            let unit = GroceryMerger.normalize(contribution.unit)
            if let match {
                match.isChecked = checked
                match.coveredQuantity = contribution.quantity
                match.unit = unit
                match.recipeSlug = contribution.recipeSlug
            } else if checked {
                context.insert(
                    IngredientCheck(
                        mealUUID: contribution.mealUUID,
                        recipeSlug: contribution.recipeSlug,
                        ingredientId: contribution.ingredientId,
                        sortIndex: contribution.sortIndex,
                        isChecked: true,
                        coveredQuantity: contribution.quantity,
                        unit: unit
                    )
                )
            }
        }
    }

    private static func resolution(
        legacyKeepsCheck: Bool,
        requiredQuantity: Double?,
        requiredUnit: String,
        ingredientId: String,
        contributions: [GroceryContribution],
        checks: [IngredientCheckRecord]
    ) -> GroceryCheckResolution {
        let identity = GroceryMerger.rowIdentity(ingredientId: ingredientId, unit: requiredUnit)
        let scoped = contributions.filter {
            GroceryMerger.rowIdentity(ingredientId: $0.ingredientId, unit: $0.unit) == identity
        }
        let outcome = GroceryCoverage.outcome(
            requiredQuantity: requiredQuantity,
            requiredUnit: requiredUnit,
            contributions: scoped,
            checks: checks
        )
        return GroceryCoverage.resolved(legacyKeepsCheck: legacyKeepsCheck, outcome: outcome)
    }

    private static func record(from check: IngredientCheck) -> IngredientCheckRecord {
        IngredientCheckRecord(
            mealUUID: check.mealUUID,
            recipeSlug: check.recipeSlug,
            ingredientId: check.ingredientId,
            sortIndex: check.sortIndex,
            isChecked: check.isChecked,
            coveredQuantity: check.coveredQuantity,
            unit: check.unit
        )
    }
}
