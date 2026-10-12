import Foundation
import SwiftData
import UIKit

/// Deterministic store for `-uitest`. Personal pantry only. No catalog import.
enum UITestFixture {
    static let recipeSlug = "ui-aksam"
    static let recipeName = "UI Akşam"
    static let mealID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    /// Clears flags a previous simulator run may have left in `UserDefaults`.
    /// The SwiftData store itself is in memory and starts empty.
    static func resetProcessDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: HouseholdTestLaunch.storageKey)
        defaults.set(false, forKey: "mealroutine.pantry.marketCoverage")
        defaults.removeObject(forKey: PantryEffectLedger.cookedKey)
        defaults.removeObject(forKey: PantryEffectLedger.crossingsKey)
        defaults.removeObject(forKey: PantryEffectLedger.armedKey)
        defaults.set(false, forKey: PantryEffectLedger.permissionKey)
        defaults.removeObject(forKey: "mealroutine.pantry.cookClaims")
        defaults.removeObject(forKey: "mealroutine.pantry.cookHeld")
        PantryNotificationPreferenceStore.save(.off, defaults)
        PantryLocationTabSession.selected = .all
    }

    @MainActor
    static func seed(in context: ModelContext) throws {
        let photoPath = try writeHeroPhoto()
        let prefs = UserPrefs(
            householdSize: 1,
            eveningsPerWeek: 1,
            hasCompletedOnboarding: true,
            createdAt: AppClock.now
        )
        context.insert(prefs)

        let recipe = Recipe(
            slug: recipeSlug,
            nameEN: "UI Evening",
            nameTR: recipeName,
            nativeName: recipeName,
            summaryEN: "Fixture dinner for UI tests.",
            summaryTR: "Arayüz testi için sabit akşam.",
            country: "TR",
            category: "main",
            unitoolsCategory: "main",
            diets: [],
            difficulty: "easy",
            baseServings: 1,
            prepMinutes: 5,
            cookMinutes: 10,
            totalMinutes: 15,
            tags: ["ui-test"],
            trDogfoodScore: 1,
            hardIngredientPenalty: 0,
            calories: 100,
            protein: 1,
            fat: 1,
            carbs: 1,
            sourceProvider: "mealroutine",
            sourceLicense: "MealRoutine original",
            sourceAttribution: "UI test fixture",
            photoURL: "",
            photoAuthor: "UI Test",
            photoLicense: "Test"
        )
        recipe.sourceImagePath = photoPath
        context.insert(recipe)

        let tomato = IngredientLine(
            ingredientId: "tomato",
            nameEN: "Tomato",
            nameTR: "Domates",
            quantity: 1,
            unit: "piece",
            scaling: "fixed",
            note: "",
            trAliasCurated: true,
            sortIndex: 0
        )
        tomato.recipe = recipe
        context.insert(tomato)

        let onion = IngredientLine(
            ingredientId: "onion",
            nameEN: "Onion",
            nameTR: "Soğan",
            quantity: 2,
            unit: "piece",
            scaling: "fixed",
            note: "",
            trAliasCurated: true,
            sortIndex: 1
        )
        onion.recipe = recipe
        context.insert(onion)

        let step = RecipeStep(textEN: "Cook.", textTR: "Pişir.", minutes: 10, sortIndex: 0)
        step.recipe = recipe
        context.insert(step)

        let week = PlanWeek(
            uuid: UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!,
            weekStart: WeekCalendar.weekStart(containing: AppClock.now),
            createdAt: AppClock.now,
            householdSize: 1
        )
        context.insert(week)
        let meal = PlannedMeal(uuid: mealID, dayOffset: 0, recipeSlug: recipeSlug, servings: 1)
        meal.week = week
        context.insert(meal)

        // Need 1 piece. Default walk takes Kiler 1 and leaves Buzdolabı at 0.
        // The plus control can move that 1 onto Buzdolabı.
        context.insert(PantryItem(
            householdID: nil,
            ingredientID: "tomato",
            displayName: "Domates",
            quantity: 1,
            unit: "piece",
            location: .pantry
        ))
        context.insert(PantryItem(
            householdID: nil,
            ingredientID: "tomato",
            displayName: "Domates",
            quantity: 2,
            unit: "piece",
            location: .refrigerator
        ))
        // Need 2, stock 1. The partial row can be switched off.
        context.insert(PantryItem(
            householdID: nil,
            ingredientID: "onion",
            displayName: "Soğan",
            quantity: 1,
            unit: "piece",
            location: .pantry
        ))
        // Group total 1 is under the minimum, so the row shows Azaldı.
        context.insert(PantryItem(
            householdID: nil,
            ingredientID: "milk",
            displayName: "Süt",
            quantity: 1,
            unit: "piece",
            location: .pantry,
            minimumQuantity: 3
        ))

        func manual(
            _ ingredientId: String,
            name: String,
            quantity: Double,
            source: GroceryLineSource
        ) {
            let item = GroceryItem(
                ingredientId: ingredientId,
                nameTR: name,
                nameEN: name,
                quantity: quantity,
                unit: "piece",
                hasUnitConflict: false,
                isChecked: false,
                isManual: true,
                sourceRaw: source.rawValue
            )
            item.week = week
            context.insert(item)
        }

        // Plan row is rebuilt from the recipe. These stay because they are manual.
        // Threshold and shortfall share one pantry-auto key, so Eşik is a separate card.
        manual(
            PantryAutoGrocery.itemKey(ingredientId: "tomato", unit: "piece"),
            name: "Domates",
            quantity: 2,
            source: .shortfall
        )
        manual(
            PantryAutoGrocery.cookGapKey(mealId: mealID.uuidString, ingredientId: "tomato", unit: "piece"),
            name: "Domates",
            quantity: 3,
            source: .cookGap
        )
        manual("manual:uitest-domates", name: "Domates", quantity: 4, source: .typed)
        manual(
            PantryAutoGrocery.itemKey(ingredientId: "milk", unit: "piece"),
            name: "Süt",
            quantity: 2,
            source: .threshold
        )

        try context.save()
    }

    /// Wide local JPEG so the hero paints without a network fetch.
    private static func writeHeroPhoto() throws -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 640))
        let image = renderer.image { context in
            UIColor(red: 0.72, green: 0.28, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-hero.jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }
}
