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
    /// Skips a repeat rebuild when meals, portions, checks, and custom amounts are unchanged.
    /// Set only after a full rebuild. Incremental check updates refresh it when the market
    /// row already exists, so a later visit does not merge the whole week again.
    private static var appliedFingerprint: Int?

    /// Drops the skip key after the catalog or the household store is replaced.
    @MainActor
    static func discardRebuildCache() {
        appliedFingerprint = nil
    }

    @MainActor
    static func rebuild(in context: ModelContext, now: Date = .now) throws {
        guard let week = try WeekPlanService.currentWeek(in: context, now: now) else { return }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return }
        let householdSize = prefs.householdSize
        let storedChecks = try context.fetch(FetchDescriptor<IngredientCheck>())
        if inputFingerprint(week: week, householdSize: householdSize, checks: storedChecks) == appliedFingerprint {
            return
        }

        let bySlug = try recipesBySlug(Set(week.meals.map(\.recipeSlug)), in: context)

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
        let checksChanged = try reconcileStoredChecks(
            contributions: contributions,
            weekMealIDs: mealIDs,
            in: context
        )
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
        if didChange || checksChanged {
            try context.save()
        }
        appliedFingerprint = inputFingerprint(
            week: week,
            householdSize: householdSize,
            checks: try context.fetch(FetchDescriptor<IngredientCheck>())
        )
    }

    @MainActor
    static func toggle(_ uuid: UUID, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        guard let item = items.first(where: { $0.uuid == uuid }) else { return }
        let turningOn = !item.isChecked
        if item.isManual {
            item.isChecked = turningOn
            try context.save()
        } else if let prepared = try preparedCoverage(for: item, in: context) {
            try writeChecks(prepared.lines, checked: turningOn, in: context)
            item.isChecked = turningOn
            item.uncoveredQuantity = nil
            let updatedRow = try applyCoverage(
                matching: prepared.identity,
                week: prepared.week,
                contributions: prepared.lines,
                in: context
            )
            try context.save()
            if updatedRow {
                try rememberFingerprint(in: context)
            }
        } else {
            item.isChecked = turningOn
            item.uncoveredQuantity = nil
            try context.save()
        }
        guard item.isChecked, turningOn else { return }
        Analytics.track(.groceryItemChecked)
        if let week = item.week, !week.groceries.isEmpty, week.groceries.allSatisfy(\.isChecked) {
            Analytics.track(.groceryListCompleted)
        }
    }

    /// Writes a new amount and keeps the stored unit and aisle.
    /// A different amount clears the check so the new figure is visible.
    /// Coverage for that row is refreshed from the recipe checks immediately.
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
        let updatedRow = item.isManual
            ? false
            : try applyCoverage(ingredientId: item.ingredientId, unit: item.unit, in: context)
        try context.save()
        if updatedRow {
            try rememberFingerprint(in: context)
        }
    }

    /// Persists one ingredient check and updates only the matching market row.
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
        let updatedRow = mealUUID == nil
            ? false
            : try applyCoverage(ingredientId: ingredientId, unit: storedUnit, in: context)
        try context.save()
        if updatedRow {
            try rememberFingerprint(in: context)
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
        return didChange
    }

    private struct PreparedCoverage {
        var week: PlanWeek
        var identity: String
        var lines: [GroceryContribution]
    }

    /// Week recipes that feed one grocery identity, loaded once for a checkbox tap.
    @MainActor
    private static func preparedCoverage(
        for item: GroceryItem,
        in context: ModelContext
    ) throws -> PreparedCoverage? {
        guard let week = try item.week ?? WeekPlanService.currentWeek(in: context) else { return nil }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return nil }
        let identity = GroceryMerger.rowIdentity(ingredientId: item.ingredientId, unit: item.unit)
        let lines = try contributions(
            for: identity,
            week: week,
            householdSize: prefs.householdSize,
            in: context
        )
        return PreparedCoverage(week: week, identity: identity, lines: lines)
    }

    @MainActor
    private static func writeChecks(
        _ contributions: [GroceryContribution],
        checked: Bool,
        in context: ModelContext
    ) throws {
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

    /// Updates one merged row from the checks that feed it. False when that row is not on the week yet.
    @MainActor
    @discardableResult
    private static func applyCoverage(
        ingredientId: String,
        unit: String,
        in context: ModelContext
    ) throws -> Bool {
        guard let week = try WeekPlanService.currentWeek(in: context) else { return false }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return false }
        let identity = GroceryMerger.rowIdentity(ingredientId: ingredientId, unit: unit)
        let lines = try contributions(
            for: identity,
            week: week,
            householdSize: prefs.householdSize,
            in: context
        )
        return try applyCoverage(matching: identity, week: week, contributions: lines, in: context)
    }

    @MainActor
    @discardableResult
    private static func applyCoverage(
        matching identity: String,
        week: PlanWeek,
        contributions: [GroceryContribution],
        in context: ModelContext
    ) throws -> Bool {
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>()).map(record(from:))
        let planned = GroceryMerger.merge(
            contributions.map {
                GrocerySourceLine(
                    ingredientId: $0.ingredientId,
                    nameTR: "",
                    nameEN: "",
                    quantity: $0.quantity,
                    unit: $0.unit
                )
            }
        )
        let plannedLine = planned.first {
            GroceryMerger.rowIdentity(ingredientId: $0.ingredientId, unit: $0.unit) == identity
        }
        let targets = week.groceries.filter {
            !$0.isManual && GroceryMerger.rowIdentity(ingredientId: $0.ingredientId, unit: $0.unit) == identity
        }
        guard !targets.isEmpty else { return false }
        for item in targets {
            let requiredQuantity = item.quantityIsCustom ? item.quantity : (plannedLine?.quantity ?? item.quantity)
            let requiredUnit = item.quantityIsCustom ? item.unit : (plannedLine?.unit ?? item.unit)
            let resolution = resolution(
                legacyKeepsCheck: item.isChecked,
                requiredQuantity: requiredQuantity,
                requiredUnit: requiredUnit,
                ingredientId: item.ingredientId,
                contributions: contributions,
                checks: checks
            )
            item.isChecked = resolution.isChecked
            item.uncoveredQuantity = resolution.uncoveredQuantity
        }
        return true
    }

    @MainActor
    private static func contributions(
        for identity: String,
        week: PlanWeek,
        householdSize: Int,
        in context: ModelContext
    ) throws -> [GroceryContribution] {
        let bySlug = try recipesBySlug(Set(week.meals.map(\.recipeSlug)), in: context)
        var lines: [GroceryContribution] = []
        for meal in week.meals {
            guard let recipe = bySlug[meal.recipeSlug] else { continue }
            let servings = ActiveServings.resolve(
                mealServings: meal.servings,
                householdSize: householdSize
            )
            for ingredient in recipe.ingredients {
                guard GroceryMerger.rowIdentity(ingredientId: ingredient.ingredientId, unit: ingredient.unit) == identity else {
                    continue
                }
                let quantity = PortionScaler.scale(
                    quantity: ingredient.quantity,
                    scaling: ingredient.scaling,
                    baseServings: recipe.baseServings,
                    householdSize: servings
                )
                lines.append(
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
        return lines
    }

    /// Week recipes only. The catalog is much larger than one week's dinners.
    @MainActor
    private static func recipesBySlug(
        _ slugs: Set<String>,
        in context: ModelContext
    ) throws -> [String: Recipe] {
        var bySlug: [String: Recipe] = [:]
        for slug in slugs {
            if let recipe = try recipe(slug: slug, in: context) {
                bySlug[recipe.slug] = recipe
            }
        }
        return bySlug
    }

    @MainActor
    private static func recipe(slug: String, in context: ModelContext) throws -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.slug == slug }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Refreshes the skip key after a cheap row update. No-ops until a full rebuild has run,
    /// so a check made before the list exists still creates that list on the next rebuild.
    @MainActor
    private static func rememberFingerprint(in context: ModelContext) throws {
        guard appliedFingerprint != nil else { return }
        guard let week = try WeekPlanService.currentWeek(in: context) else { return }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return }
        let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
        appliedFingerprint = inputFingerprint(
            week: week,
            householdSize: prefs.householdSize,
            checks: checks
        )
    }

    private static func inputFingerprint(
        week: PlanWeek,
        householdSize: Int,
        checks: [IngredientCheck]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(householdSize)
        hasher.combine(week.weekStart.timeIntervalSinceReferenceDate)
        for meal in week.meals.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
            hasher.combine(meal.uuid)
            hasher.combine(meal.recipeSlug)
            hasher.combine(meal.servings)
        }
        let ordered = checks.sorted { lhs, rhs in
            let left = "\(lhs.mealUUID?.uuidString ?? "")|\(lhs.sortIndex)|\(lhs.ingredientId)|\(lhs.recipeSlug)"
            let right = "\(rhs.mealUUID?.uuidString ?? "")|\(rhs.sortIndex)|\(rhs.ingredientId)|\(rhs.recipeSlug)"
            return left < right
        }
        for check in ordered {
            hasher.combine(check.mealUUID?.uuidString ?? "")
            hasher.combine(check.recipeSlug)
            hasher.combine(check.ingredientId)
            hasher.combine(check.sortIndex)
            hasher.combine(check.isChecked)
            hasher.combine(check.coveredQuantity == nil)
            hasher.combine(check.coveredQuantity ?? 0)
            hasher.combine(check.unit)
        }
        let autoRows = week.groceries
            .filter { !$0.isManual }
            .sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        hasher.combine(autoRows.count)
        for item in autoRows {
            hasher.combine(item.uuid)
            hasher.combine(item.ingredientId)
            hasher.combine(item.unit)
            hasher.combine(item.quantityIsCustom)
            if item.quantityIsCustom {
                hasher.combine(item.quantity == nil)
                hasher.combine(item.quantity ?? 0)
            }
        }
        return hasher.finalize()
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
