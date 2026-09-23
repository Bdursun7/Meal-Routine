import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "com.mealroutine.app", category: "seed")

/// Imports `Recipes/recipes.v1.json` into SwiftData the first time, and again
/// if a previous import stopped short of the file's recipe count.
enum RecipeSeedService {
    @MainActor
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) throws {
        let catalog = try RecipeCatalogLoader.load(bundle: bundle)
        guard catalog.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(catalog.schemaVersion)
        }

        let existingCount = try context.fetchCount(FetchDescriptor<Recipe>())
        if existingCount == catalog.recipes.count {
            return
        }

        if existingCount > 0 {
            let stale = try context.fetch(FetchDescriptor<Recipe>())
            for recipe in stale {
                context.delete(recipe)
            }
        }

        let aliases = RecipeCatalogLoader.loadAliases(bundle: bundle)
        for dto in catalog.recipes {
            insert(dto, aliases: aliases, into: context)
        }
        try context.save()
        logger.info("Seeded bundled recipes into SwiftData")
    }

    @MainActor
    private static func insert(_ dto: RecipeDTO, aliases: [String: String], into context: ModelContext) {
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
            photoURL: dto.photo?.url ?? "",
            photoAuthor: dto.photo?.author ?? "",
            photoLicense: dto.photo?.license ?? ""
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
                note: ingredient.note ?? "",
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
