import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.mealroutine.app", category: "seed")

/// Imports `Recipes/recipes.v1.json` when the bundled catalog fingerprint changes.
///
/// Skip only when that fingerprint matches the last successful import and the store
/// still has every catalog recipe. Afterward, orphaned `PlannedMeal.recipeSlug`s are
/// repaired and the current week's grocery list is rebuilt.
enum RecipeSeedService {
    @MainActor
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main, now: Date = .now) async throws {
        let bundled = try RecipeCatalogLoader.loadBundled(bundle: bundle)
        guard bundled.file.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(bundled.file.schemaVersion)
        }

        let existingCount = try context.fetchCount(FetchDescriptor<Recipe>())
        let stored = try storedFingerprint(in: context)
        if !CatalogFingerprint.shouldSkipImport(
            storedFingerprint: stored,
            currentFingerprint: bundled.fingerprint,
            existingRecipeCount: existingCount,
            catalogRecipeCount: bundled.file.recipes.count
        ) {
            try await importCatalog(bundled, bundle: bundle, into: context)
            GroceryListService.discardRebuildCache()
            logger.info("Seeded bundled recipes into SwiftData")
        }

        _ = try PlanIntegrityService.repair(in: context, now: now)
        // Rebuild on every launch after the orphan pass. Unchanged rows stay as they
        // are, including checked state and manual extras. A same-slug ingredient edit
        // still refreshes quantities, and a rebuild that failed after import is retried
        // next launch. A current-week regenerate copies manual extras onto the new week
        // first; auto rows are then filled from those meals.
        try GroceryListService.rebuild(in: context, now: now)
    }

    @MainActor
    private static func importCatalog(
        _ bundled: BundledCatalog,
        bundle: Bundle,
        into context: ModelContext
    ) async throws {
        // Save deletes before inserting the same slugs. One save can fail the unique
        // constraint on Recipe.slug when new rows collide with rows still queued for
        // deletion. A crash after that delete leaves a short store; shouldSkipImport
        // refuses a matching fingerprint until every catalog recipe is present again.
        CatalogIndexCache.invalidate()
        let staleRecipes = try context.fetch(FetchDescriptor<Recipe>())
        if !staleRecipes.isEmpty {
            for (index, recipe) in staleRecipes.enumerated() {
                context.delete(recipe)
                if index % 40 == 39 {
                    await Task.yield()
                }
            }
            try context.save()
        }

        let aliases = RecipeCatalogLoader.loadAliases(bundle: bundle)
        for (index, dto) in bundled.file.recipes.enumerated() {
            insert(dto, aliases: aliases, into: context)
            if index % 40 == 39 {
                try context.save()
                await Task.yield()
            }
        }
        try writeFingerprint(bundled.fingerprint, in: context)
        try context.save()
    }

    @MainActor
    private static func writeFingerprint(_ fingerprint: String, in context: ModelContext) throws {
        let states = try context.fetch(FetchDescriptor<CatalogImportState>())
        if let current = states.max(by: { $0.importedAt < $1.importedAt }) {
            current.fingerprint = fingerprint
            current.importedAt = .now
            for extra in states where extra !== current {
                context.delete(extra)
            }
        } else {
            context.insert(CatalogImportState(fingerprint: fingerprint))
        }
    }

    @MainActor
    private static func storedFingerprint(in context: ModelContext) throws -> String? {
        let states = try context.fetch(FetchDescriptor<CatalogImportState>())
        return states.max(by: { $0.importedAt < $1.importedAt })?.fingerprint
    }

    @MainActor
    private static func insert(_ dto: RecipeDTO, aliases: [String: String], into context: ModelContext) {
        let photo = RecipePhoto.persisted(
            url: dto.photo?.url,
            author: dto.photo?.author,
            license: dto.photo?.license
        )
        let recipe = Recipe(
            slug: dto.id,
            nameEN: dto.name.en ?? "",
            nameTR: nonEmpty(dto.name.tr) ?? nonEmpty(dto.name.en) ?? dto.id,
            nativeName: dto.nativeName ?? "",
            summaryEN: dto.summary?.en ?? "",
            summaryTR: dto.summary?.tr ?? "",
            country: dto.country,
            category: dto.category,
            unitoolsCategory: dto.unitoolsCategory,
            diets: dto.diets,
            difficulty: dto.difficulty,
            baseServings: max(dto.baseServings, 1),
            prepMinutes: dto.prepMinutes,
            cookMinutes: dto.cookMinutes,
            totalMinutes: dto.totalMinutes,
            tags: dto.tags,
            trDogfoodScore: dto.trDogfoodScore,
            hardIngredientPenalty: dto.hardIngredientPenalty,
            calories: dto.nutritionPerServing?.calories ?? 0,
            protein: dto.nutritionPerServing?.protein ?? 0,
            fat: dto.nutritionPerServing?.fat ?? 0,
            carbs: dto.nutritionPerServing?.carbs ?? 0,
            sourceProvider: dto.source.provider ?? "unitools",
            sourceLicense: dto.source.license ?? "CC BY-SA 4.0",
            sourceAttribution: dto.source.attribution ?? "UniTools — theunitools.com",
            photoURL: photo.url,
            photoAuthor: photo.author,
            photoLicense: photo.license
        )
        context.insert(recipe)

        for (index, ingredient) in dto.ingredients.enumerated() {
            let turkish = nonEmpty(ingredient.name.tr)
                ?? aliases[ingredient.id]
                ?? nonEmpty(ingredient.name.en)
                ?? ingredient.id
            let line = IngredientLine(
                ingredientId: ingredient.id,
                nameEN: ingredient.name.en ?? "",
                nameTR: turkish,
                quantity: ingredient.quantity,
                unit: ingredient.unit,
                scaling: ingredient.scaling,
                note: ingredient.note?.en ?? "",
                noteTR: ingredient.note?.tr ?? "",
                trAliasCurated: ingredient.trAliasCurated,
                sortIndex: index
            )
            context.insert(line)
            line.recipe = recipe
        }

        for (index, step) in dto.steps.enumerated() {
            let model = RecipeStep(
                textEN: step.text.en ?? "",
                textTR: step.text.tr ?? "",
                minutes: step.minutes,
                sortIndex: index
            )
            context.insert(model)
            model.recipe = recipe
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
