import Foundation
import SwiftData

/// Rebuilds the current week's shopping list from planned meals.
/// Manual rows and checked state on matching ingredient+unit rows are kept.
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

        for meal in week.meals {
            guard let recipe = bySlug[meal.recipeSlug] else { continue }
            for ingredient in recipe.ingredients {
                let quantity = PortionScaler.scale(
                    quantity: ingredient.quantity,
                    scaling: ingredient.scaling,
                    baseServings: recipe.baseServings,
                    householdSize: prefs.householdSize
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
        var used: Set<UUID> = []
        var didChange = false

        for line in merged {
            let normalizedUnit = GroceryMerger.normalize(line.unit)
            if let match = autoItems.first(where: {
                $0.ingredientId == line.ingredientId
                    && GroceryMerger.normalize($0.unit) == normalizedUnit
                    && !used.contains($0.uuid)
            }) {
                used.insert(match.uuid)
                if match.nameTR != line.nameTR
                    || match.nameEN != line.nameEN
                    || match.quantity != line.quantity
                    || match.unit != normalizedUnit
                    || match.hasUnitConflict != line.hasUnitConflict {
                    match.nameTR = line.nameTR
                    match.nameEN = line.nameEN
                    match.quantity = line.quantity
                    match.unit = normalizedUnit
                    match.hasUnitConflict = line.hasUnitConflict
                    didChange = true
                }
            } else {
                let item = GroceryItem(
                    ingredientId: line.ingredientId,
                    nameTR: line.nameTR,
                    nameEN: line.nameEN,
                    quantity: line.quantity,
                    unit: normalizedUnit,
                    hasUnitConflict: line.hasUnitConflict,
                    isChecked: false,
                    isManual: false
                )
                context.insert(item)
                item.week = week
                didChange = true
            }
        }

        for item in autoItems where !used.contains(item.uuid) {
            context.delete(item)
            didChange = true
        }
        if didChange {
            try context.save()
        }
    }

    @MainActor
    static func toggle(_ uuid: UUID, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        guard let item = items.first(where: { $0.uuid == uuid }) else { return }
        item.isChecked.toggle()
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
