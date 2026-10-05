import SwiftData
import XCTest
@testable import MealRoutine

@MainActor
final class RecipeImportTests: XCTestCase {
    func testURLKeyDropsTrackingAndKeepsThePath() {
        let left = RecipeSourceService.normalizedKey("https://www.Example.com/tarif/corba/?utm_source=ig&fbclid=abc&id=1")
        let right = RecipeSourceService.normalizedKey("http://example.com/tarif/corba?id=1&fbclid=zzz#photo")
        XCTAssertEqual(left, right)
        XCTAssertEqual(left, "https://example.com/tarif/corba?id=1")
        XCTAssertNil(RecipeSourceService.publicURL("ftp://example.com/a"))
        XCTAssertNil(RecipeSourceService.normalizedKey("   "))
        let instagram = URL(string: "https://www.instagram.com/p/ABC123/?igsh=1")!
        XCTAssertEqual(RecipeSourceService.platform(for: instagram), .instagram)
    }

    func testShareAssemblyKeepsOneURLTitleTextAndImage() {
        let url = SharePayloadAssembly.makeCapture(
            urls: ["https://example.com/a?utm_source=ig"],
            titles: [],
            texts: [],
            imagePath: nil,
            sourceHint: nil
        )
        XCTAssertEqual(url?.urlString, "https://example.com/a?utm_source=ig")
        XCTAssertEqual(url?.sourcePlatform, .website)

        let titled = SharePayloadAssembly.makeCapture(
            urls: ["https://www.instagram.com/p/abc"],
            titles: ["Beyti"],
            texts: [],
            imagePath: nil,
            sourceHint: "Instagram"
        )
        XCTAssertEqual(titled?.title, "Beyti")
        XCTAssertEqual(titled?.sourcePlatform, .instagram)

        let textOnly = SharePayloadAssembly.makeCapture(
            urls: [],
            titles: [],
            texts: ["Akşam için mantı"],
            imagePath: nil,
            sourceHint: "Notes"
        )
        XCTAssertEqual(textOnly?.text, "Akşam için mantı")
        XCTAssertEqual(textOnly?.sourcePlatform, .notes)
        XCTAssertNil(textOnly?.urlString)

        let image = SharePayloadAssembly.makeCapture(
            urls: ["https://youtu.be/abc"],
            titles: [],
            texts: [],
            imagePath: "RecipeImages/a.jpg",
            sourceHint: nil
        )
        XCTAssertEqual(image?.imagePath, "RecipeImages/a.jpg")
        XCTAssertEqual(image?.sourcePlatform, .youtube)

        let titleAndImage = SharePayloadAssembly.makeCapture(
            urls: [],
            titles: ["Köfte"],
            texts: [],
            imagePath: "RecipeImages/b.jpg",
            sourceHint: nil
        )
        XCTAssertEqual(titleAndImage?.title, "Köfte")
        XCTAssertNotNil(titleAndImage?.imagePath)

        XCTAssertNil(SharePayloadAssembly.makeCapture(
            urls: ["ftp://example.com/a"],
            titles: ["ftp://example.com/a"],
            texts: ["ftp://example.com/a"],
            imagePath: nil,
            sourceHint: nil
        ))

        let many = SharePayloadAssembly.makeCapture(
            urls: ["https://example.com/first", "https://example.com/second"],
            titles: ["İlk", "İkinci"],
            texts: ["not", "daha"],
            imagePath: "RecipeImages/c.jpg",
            sourceHint: nil
        )
        XCTAssertEqual(many?.urlString, "https://example.com/first")
        XCTAssertEqual(many?.title, "İlk")
        XCTAssertEqual(many?.text, "not")
    }

    func testQuickSaveKeepsSourceAndDoesNotRequireIngredients() throws {
        let context = try makeContext()
        var capture = RecipeCapture(
            urlString: "https://www.Example.com/tarif/corba/?utm_source=ig&fbclid=1",
            title: "Mercimek",
            text: "Akşam dene",
            imagePath: "RecipeImages/m.jpg",
            sourcePlatform: .website
        )
        let saved = try RecipeCollectionService.quickSave(capture, in: context)
        XCTAssertEqual(saved.nameTR, "Mercimek")
        XCTAssertEqual(saved.sourceURL, capture.urlString)
        XCTAssertEqual(saved.sourcePlatform, .website)
        XCTAssertEqual(saved.sourceImagePath, "RecipeImages/m.jpg")
        XCTAssertEqual(saved.collectionState, .savedToTry)
        XCTAssertEqual(saved.origin, .savedExternal)
        XCTAssertTrue(saved.ingredients.isEmpty)
        XCTAssertFalse(ImportedRecipeEligibility.allowsPlanning(saved))

        capture.allowDuplicate = false
        let again = try RecipeCollectionService.quickSave(capture, in: context)
        XCTAssertEqual(again.slug, saved.slug)
        XCTAssertEqual(saved.nameTR, "Mercimek")

        capture.allowDuplicate = true
        capture.urlString = "https://example.com/tarif/corba?fbclid=2"
        let copy = try RecipeCollectionService.quickSave(capture, in: context)
        XCTAssertNotEqual(copy.slug, saved.slug)

        let other = RecipeCapture(urlString: "https://example.com/baska", title: "Başka")
        let second = try RecipeCollectionService.quickSave(other, in: context)
        XCTAssertNotEqual(second.slug, saved.slug)
    }

    func testCompletionRules() {
        var form = RecipeForm.emptyManual()
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingName))
        form.name = "   "
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingName))
        form.name = "Köfte"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingIngredient))
        form.ingredients = [RecipeFormIngredient(name: "kıyma")]
        let namedOnly = RecipeValidationService.validate(form).issues
        XCTAssertTrue(namedOnly.contains(.missingQuantity))
        XCTAssertTrue(namedOnly.contains(.missingUnit))
        form.ingredients[0].quantity = 400
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingUnit))
        form.ingredients[0].unit = "g"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingInstruction))
        form.steps = ["Yoğur.", ""]
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.emptyInstruction))
        form.steps = ["Yoğur."]
        form.servings = 0
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingServings))
        form.servings = 4
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        form.ingredients.append(RecipeFormIngredient())
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        form.ingredients.append(RecipeFormIngredient(name: "tuz", quantity: 1, isOptional: true))
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingUnit))
        form.ingredients[2].unit = "tsp"
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
    }

    func testNumericFieldsRejectJunkAndKeepRealNumbers() {
        var form = readyForm()
        form.servings = 4
        form.servingsText = "abc"
        let junkServings = RecipeValidationService.validate(form).issues
        XCTAssertTrue(junkServings.contains(.invalidServings))
        XCTAssertFalse(junkServings.contains(.missingServings))
        XCTAssertNotEqual(RecipeValidationService.validate(form), .valid)
        XCTAssertNil(RecipeValidationService.resolvedServings(form))
        XCTAssertEqual(
            RecipeValidationService.message(for: .servings, in: form),
            RecipeValidationIssue.invalidServings.message
        )

        form.servingsText = "0"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.missingServings))
        form.servingsText = "2.5"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.invalidServings))
        form.servingsText = "1000"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.servingsTooLong))
        form.servingsText = ""
        form.servings = 4
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)

        form.ingredients[0].quantity = 400
        form.ingredients[0].quantityText = "biraz"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.invalidQuantity))
        XCTAssertNil(RecipeValidationService.resolvedQuantity(form.ingredients[0]))
        form.ingredients[0].quantityText = "1,5"
        XCTAssertEqual(RecipeValidationService.resolvedQuantity(form.ingredients[0]), 1.5)
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        form.ingredients[0].quantityText = ""
        form.ingredients[0].quantity = 400

        form.prepMinutesText = "abc"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.invalidMinutes))
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .prepMinutes)
        XCTAssertNil(RecipeValidationService.resolvedMinutes(text: form.prepMinutesText, stored: 15))
        form.prepMinutesText = ""
        form.prepMinutes = nil
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        form.cookMinutesText = "0"
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        XCTAssertNil(RecipeValidationService.resolvedMinutes(text: "0", stored: nil))
    }

    func testFieldLengthLimits() {
        var form = readyForm()
        form.name = String(repeating: "a", count: RecipeFieldLimits.name + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.nameTooLong))
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .name)
        form.name = String(repeating: "a", count: RecipeFieldLimits.name)
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)

        form.ingredients[0].name = String(repeating: "m", count: RecipeFieldLimits.ingredientName + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.ingredientNameTooLong))
        form.ingredients[0].name = "kıyma"
        form.ingredients[0].preparationNote = String(repeating: "n", count: RecipeFieldLimits.preparationNote + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.preparationNoteTooLong))
        form.ingredients[0].preparationNote = ""
        form.steps = [String(repeating: "s", count: RecipeFieldLimits.step + 1)]
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.stepTooLong))
        form.steps = ["Yoğur."]
        form.notes = String(repeating: "n", count: RecipeFieldLimits.notes + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.notesTooLong))
        form.notes = ""
        form.category = String(repeating: "k", count: RecipeFieldLimits.category + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.categoryTooLong))
        form.category = ""
        form.cuisine = String(repeating: "m", count: RecipeFieldLimits.cuisine + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.cuisineTooLong))
        form.cuisine = ""
        form.sourceURL = String(repeating: "u", count: RecipeFieldLimits.sourceURL + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.sourceURLTooLong))
        form.sourceURL = ""
        form.sourceTitle = String(repeating: "t", count: RecipeFieldLimits.sourceTitle + 1)
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.sourceTitleTooLong))
        form.sourceTitle = ""
        form.prepMinutesText = "12345"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.minutesTooLong))
        form.prepMinutesText = ""
        form.ingredients[0].quantityText = "1234567"
        XCTAssertTrue(RecipeValidationService.validate(form).issues.contains(.quantityTooLong))
        form.ingredients[0].quantityText = ""
        form.ingredients[0].quantity = 400
        XCTAssertEqual(RecipeValidationService.validate(form), .valid)
        XCTAssertEqual(
            RecipeTextLimit.clamp(String(repeating: "a", count: 200), maxCharacters: RecipeFieldLimits.name).count,
            RecipeFieldLimits.name
        )
    }

    func testEditorFocusesTheTopmostMissingFieldAndKeepsUnitCodes() {
        var form = RecipeForm.emptyManual()
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .name)
        form.name = "Köfte"
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .servings)
        form.servings = 4
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .ingredientName(0))
        form.ingredients = [RecipeFormIngredient(name: "kıyma", unit: "adet")]
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .ingredientQuantity(0))
        form.ingredients[0].quantity = 400
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .step(0))
        form.ingredients[0].unit = ""
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .ingredientUnit(0))
        XCTAssertEqual(
            RecipeValidationService.message(for: .ingredientUnit(0), in: form),
            "Her malzemenin bir birimi olsun"
        )
        form.ingredients[0].unit = "Birim yok"
        XCTAssertEqual(RecipeValidationService.invalidFields(in: form).first, .ingredientUnit(0))
        XCTAssertEqual(RecipeUnitChoices.canonical("adet"), "piece")
        XCTAssertEqual(RecipeUnitChoices.canonical("yemek kaşığı"), "tbsp")
        XCTAssertEqual(RecipeUnitChoices.canonical(""), "")
        XCTAssertEqual(RecipeUnitChoices.canonical("piece"), "piece")
    }

    func testReadyRecipeCanBePlannedAndSavedToTryCannot() throws {
        let context = try makeContext()
        let capture = RecipeCapture(urlString: "https://example.com/kofte", title: "Köfte")
        let trying = try RecipeCollectionService.quickSave(capture, in: context)
        XCTAssertFalse(ImportedRecipeEligibility.allowsPlanning(trying))

        var form = RecipeCollectionService.form(from: trying)
        form.name = "Köfte"
        form.servings = 4
        form.ingredients = [RecipeFormIngredient(name: "kıyma", quantity: 400, unit: "g")]
        form.steps = ["Yoğur ve pişir."]
        let ready = try RecipeCollectionService.save(form, slug: trying.slug, in: context)
        XCTAssertEqual(ready.collectionState, .readyToCook)
        XCTAssertEqual(ready.slug, trying.slug)
        XCTAssertTrue(ImportedRecipeEligibility.allowsPlanning(ready))
        XCTAssertEqual(ready.ingredients.first?.quantity, 400)
        XCTAssertEqual(ready.sourceURL, "https://example.com/kofte")

        let prefs = TestFixtures.prefs()
        var unknown = TestFixtures.candidate(ready.slug, minutes: 0)
        unknown.timeIsUnknown = true
        XCTAssertTrue(PersonalizedScoringService.isEligible(
            unknown,
            preferences: prefs,
            memory: nil,
            blockedSlugs: []
        ))
    }

    func testGroceryKeepsCompletedQuantities() throws {
        let context = try makeContext()
        let now = TestFixtures.now
        let prefs = UserPrefs(householdSize: 2, hasCompletedOnboarding: true, createdAt: now)
        context.insert(prefs)
        var form = RecipeForm.emptyManual()
        form.name = "Çorba"
        form.servings = 2
        form.ingredients = [
            RecipeFormIngredient(name: "mercimek", quantity: 2, unit: "g"),
            RecipeFormIngredient(name: "tuz", quantity: 1, unit: "tsp", isOptional: true),
        ]
        form.steps = ["Pişir."]
        let recipe = try RecipeCollectionService.save(form, slug: nil, in: context, now: now)
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), createdAt: now, householdSize: 2)
        context.insert(week)
        let meal = PlannedMeal(dayOffset: 0, recipeSlug: recipe.slug, servings: 2)
        context.insert(meal)
        meal.week = week
        meal.titleSnapshot = recipe.displayName
        try context.save()
        try GroceryListService.rebuild(in: context, now: now)
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        XCTAssertTrue(items.contains { $0.nameTR == "mercimek" && $0.quantity == 2 })
        XCTAssertTrue(items.contains { $0.ingredientId.hasSuffix("|optional") })
    }

    func testManualRecipeAndMealMemoryStayOnTheExistingPath() throws {
        let context = try makeContext()
        var form = RecipeForm.emptyManual()
        form.name = "Mantı"
        form.servings = 2
        form.ingredients = [RecipeFormIngredient(name: "un", quantity: 2, unit: "g")]
        form.steps = ["Aç."]
        let recipe = try RecipeCollectionService.save(form, slug: nil, in: context)
        XCTAssertEqual(recipe.origin, .manual)
        XCTAssertEqual(recipe.collectionState, .readyToCook)
        try WeekPlanService.setFavorite(slug: recipe.slug, loved: true, in: context)
        let memory = try MealMemoryService.snapshots(in: context)[recipe.slug]
        XCTAssertEqual(memory?.timesCooked, 0)
        XCTAssertTrue(memory?.isFavorite == true)
        var fresh = MealMemorySnapshot(recipeID: recipe.slug)
        MealMemoryReducer.apply(event: .imported, at: TestFixtures.now, to: &fresh)
        XCTAssertEqual(fresh.timesCooked, 0)
        XCTAssertEqual(fresh.lovedCount, 0)
    }

    func testPlaceReadyRecipeLeavesCookedEveningsUntouched() throws {
        UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: MealExposureLog.storageKey) }
        let context = try makeContext()
        let now = TestFixtures.now
        let prefs = UserPrefs(householdSize: 2, hasCompletedOnboarding: true, createdAt: now)
        context.insert(prefs)
        let week = PlanWeek(weekStart: WeekCalendar.weekStart(containing: now), createdAt: now, householdSize: 2)
        context.insert(week)
        let today = WeekCalendar.dayOffset(for: now, weekStart: week.weekStart)
        let other = today == 6 ? 0 : today + 1
        let cooked = PlannedMeal(dayOffset: today, recipeSlug: "pilav", servings: 2, cookedAt: now)
        let open = PlannedMeal(dayOffset: other, recipeSlug: "corba", servings: 2)
        context.insert(cooked)
        context.insert(open)
        cooked.week = week
        open.week = week
        try context.save()

        var form = RecipeForm.emptyManual()
        form.name = "Mercimek"
        form.origin = .savedExternal
        form.servings = 2
        form.totalMinutes = 30
        form.ingredients = [RecipeFormIngredient(name: "mercimek", quantity: 1, unit: "g")]
        form.steps = ["Pişir."]
        let saved = try RecipeCollectionService.save(form, slug: nil, in: context, now: now)
        try WeekPlanService.placeImportedRecipe(slug: saved.slug, in: context, now: now)

        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let cookedMeal = try XCTUnwrap(meals.first { $0.dayOffset == today })
        let openMeal = try XCTUnwrap(meals.first { $0.dayOffset == other })
        XCTAssertEqual(cookedMeal.recipeSlug, "pilav")
        XCTAssertEqual(openMeal.recipeSlug, saved.slug)
        XCTAssertEqual(openMeal.titleSnapshot, "Mercimek")
        let displaced = try MealMemoryService.snapshots(in: context)["corba"]
        XCTAssertEqual(displaced?.timesReplaced ?? 0, 0)
    }

    func testCatalogGuardLeavesPersonalRecipesOutOfBundledCount() {
        XCTAssertTrue(CatalogRecipeGuard.isBundled(originRaw: ""))
        XCTAssertTrue(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.builtIn.rawValue))
        XCTAssertFalse(CatalogRecipeGuard.isBundled(originRaw: "imported"))
        XCTAssertFalse(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.savedExternal.rawValue))
        XCTAssertFalse(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.manual.rawValue))
    }

    func testLibrarySearchFindsSavedRecipesAndSortsBySaveDate() {
        let saved = RecipeBrowseItem(
            slug: "imp",
            displayName: "Çorba",
            nameEN: "",
            country: "",
            totalMinutes: 30,
            protein: "",
            diets: [],
            tags: [],
            isLoved: false,
            origin: RecipeOrigin.savedExternal.rawValue,
            collectionState: RecipeCollectionState.savedToTry.rawValue,
            importedAt: TestFixtures.now,
            searchBlob: "mercimek kaynak sitesi"
        )
        let bundled = RecipeBrowseItem(
            slug: "cat",
            displayName: "Köfte",
            nameEN: "",
            country: "TR",
            totalMinutes: 40,
            protein: "",
            diets: [],
            tags: [],
            isLoved: false
        )
        let found = RecipeBrowse.filter(
            [bundled, saved],
            query: RecipeBrowseQuery(searchText: "mercimek", library: .savedToTry)
        )
        XCTAssertEqual(found.map(\.slug), ["imp"])
        let sorted = RecipeBrowse.filter(
            [bundled, saved],
            query: RecipeBrowseQuery(sort: .recentlyAdded)
        )
        XCTAssertEqual(sorted.first?.slug, "imp")
    }

    func testTypedNumbersAndCatalogUnitsAreWhatGetsSaved() throws {
        let context = try makeContext()
        var form = readyForm()
        form.servings = nil
        form.servingsText = "3"
        form.prepMinutesText = "20"
        form.ingredients = [RecipeFormIngredient(name: "mercimek", quantityText: "1,5", unit: "adet")]
        let recipe = try RecipeCollectionService.save(form, slug: nil, in: context)
        XCTAssertEqual(recipe.baseServings, 3)
        XCTAssertEqual(recipe.prepMinutes, 20)
        XCTAssertEqual(recipe.timeIsUnknown, false)
        XCTAssertEqual(recipe.ingredients.first?.quantity, 1.5)
        XCTAssertEqual(recipe.ingredients.first?.unit, "piece")

        form.servingsText = "abc"
        form.servings = 0
        do {
            _ = try RecipeCollectionService.save(form, slug: recipe.slug, in: context)
            XCTFail("Junk servings should not save")
        } catch let error as RecipeCollectionError {
            guard case .incomplete(let issues) = error else {
                return XCTFail("Expected incomplete, got \(error)")
            }
            XCTAssertTrue(issues.contains(.invalidServings))
        } catch {
            XCTFail("Expected incomplete, got \(error)")
        }
        XCTAssertEqual(recipe.baseServings, 3)
    }

    private func readyForm() -> RecipeForm {
        var form = RecipeForm.emptyManual()
        form.name = "Köfte"
        form.servings = 4
        form.ingredients = [RecipeFormIngredient(name: "kıyma", quantity: 400, unit: "g")]
        form.steps = ["Yoğur."]
        return form
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return container.mainContext
    }
}
