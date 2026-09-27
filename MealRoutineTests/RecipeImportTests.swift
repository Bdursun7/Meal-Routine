import SwiftData
import XCTest
@testable import MealRoutine

@MainActor
final class RecipeImportTests: XCTestCase {
    func testURLNormalizationDropsTrackingAndKeepsIdentity() {
        let left = URLNormalizer.normalizedString("https://www.Example.com/tarif/corba/?utm_source=ig&fbclid=abc&id=1")
        let right = URLNormalizer.normalizedString("http://example.com/tarif/corba?id=1&fbclid=zzz")
        XCTAssertEqual(left, right)
        XCTAssertEqual(URLNormalizer.classify("ftp://example.com/a"), .unsupportedURL("ftp://example.com/a"))
        XCTAssertEqual(URLNormalizer.classify("   "), .empty)
        let instagram = URL(string: "https://www.instagram.com/p/ABC123/?igsh=1")!
        XCTAssertEqual(URLNormalizer.platform(for: instagram), .instagram)
        XCTAssertEqual(URLNormalizer.sourceKey(for: instagram), "instagram:ABC123")
    }

    func testTimeAndServingsAreNotInvented() {
        XCTAssertEqual(TimeParser.minutes(fromISO8601: "PT1H30M"), 90)
        XCTAssertEqual(TimeParser.minutes(fromISO8601: "PT45M"), 45)
        XCTAssertNil(TimeParser.minutes(fromISO8601: "PT30S"))
        XCTAssertNil(TimeParser.minutes(fromISO8601: "soon"))
        XCTAssertEqual(TimeParser.minutes(fromText: "1 saat 15 dk"), 75)
        XCTAssertNil(TimeParser.minutes(fromText: "bir süre"))
        let range = ServingParser.parse("4-6 kişilik")
        XCTAssertEqual(range.count, 4)
        XCTAssertTrue(range.isUncertain)
        XCTAssertNil(ServingParser.parse("birkaç").count)
    }

    func testIngredientParserPreservesOriginalTextAndDoesNotInventQuantity() {
        let salt = IngredientParser.parse(line: "tuz", sortOrder: 0)
        XCTAssertEqual(salt.name, "tuz")
        XCTAssertNil(salt.quantity)
        XCTAssertTrue(salt.isUncertain)
        XCTAssertEqual(salt.originalText, "tuz")
        XCTAssertTrue(salt.includeInGrocery)

        let oil = IngredientParser.parse(line: "2 yemek kaşığı zeytinyağı", sortOrder: 1)
        XCTAssertEqual(oil.quantity, 2)
        XCTAssertEqual(oil.unit, "tbsp")
        XCTAssertEqual(oil.name, "zeytinyağı")
        XCTAssertFalse(oil.isUncertain)

        let garlic = IngredientParser.parse(line: "1-2 diş sarımsak, ezilmiş", sortOrder: 2)
        XCTAssertEqual(garlic.quantity, 1)
        XCTAssertNotEqual(garlic.quantity, 1.5)
        XCTAssertEqual(garlic.unit, "clove")
        XCTAssertEqual(garlic.name, "sarımsak")
        XCTAssertEqual(garlic.preparationNote, "ezilmiş")
        XCTAssertTrue(garlic.isUncertain)

        let flour = IngredientParser.parse(line: "1/2 su bardağı un (isteğe bağlı)", sortOrder: 3)
        XCTAssertEqual(flour.quantity ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(flour.unit, "cup")
        XCTAssertEqual(flour.name, "un")
        XCTAssertTrue(flour.isOptional)
        XCTAssertFalse(flour.isUncertain)
    }

    func testPastedTextFindsTitleIngredientsAndSteps() {
        let text = """
        Mercimek çorbası
        4 kişilik
        Hazırlık: 15 dk
        Malzemeler
        1 su bardağı kırmızı mercimek
        tuz
        Yapılışı
        1. Mercimeği yıkayın.
        2. Pişirin.
        """
        let document = RecipeTextParser.document(from: text)
        XCTAssertEqual(document.title, "Mercimek çorbası")
        XCTAssertEqual(document.servings, 4)
        XCTAssertEqual(document.prepMinutes, 15)
        XCTAssertNil(document.totalMinutes)
        XCTAssertEqual(document.ingredients.map(\.name), ["kırmızı mercimek", "tuz"])
        XCTAssertNil(document.ingredients[1].quantity)
        XCTAssertEqual(document.instructions.map(\.text), ["Mercimeği yıkayın.", "Pişirin."])
        XCTAssertFalse(document.instructions[0].isUncertain)
    }

    func testJSONLDExtractionDoesNotFillMissingTime() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Domates Soup",
         "recipeIngredient":["2 adet domates","tuz"],
         "recipeInstructions":[{"@type":"HowToStep","text":"Doğrayın."}],
         "prepTime":"PT10M","recipeYield":"3"}
        </script>
        <title>Ignored</title>
        </head></html>
        """
        let url = URL(string: "https://recipes.example/soup")!
        let result = RecipeExtractionService.extract(html: html, sourceURL: url)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.document.title, "Domates Soup")
        XCTAssertEqual(result.document.prepMinutes, 10)
        XCTAssertNil(result.document.cookMinutes)
        XCTAssertNil(result.document.totalMinutes)
        XCTAssertEqual(result.document.servings, 3)
        XCTAssertEqual(result.document.ingredients[0].quantity, 2)
        XCTAssertEqual(result.document.ingredients[0].unit, "piece")
        XCTAssertNil(result.document.ingredients[1].quantity)
        XCTAssertEqual(result.document.instructions.map(\.text), ["Doğrayın."])
        XCTAssertGreaterThan(result.document.extractionConfidence ?? 0, 0.8)
    }

    func testMetadataFallbackAndMissingRecipe() {
        let html = """
        <html><head>
        <meta property="og:title" content="Sadece başlık">
        <title>Sayfa</title>
        </head><body><p>Merhaba</p></body></html>
        """
        let url = URL(string: "https://instagram.com/p/no-recipe")!
        let result = RecipeExtractionService.extract(html: html, sourceURL: url)
        XCTAssertEqual(result.document.title, "Sadece başlık")
        XCTAssertNil(result.failure)
        XCTAssertTrue(result.document.warnings.contains(.socialWithoutRecipe))

        let empty = RecipeExtractionService.extract(html: "<html></html>", sourceURL: URL(string: "https://example.com/x")!)
        XCTAssertEqual(empty.failure, .missingRecipeData)
    }

    func testFailureMapping() {
        XCTAssertEqual(ImportFailure.map(URLError(.timedOut)), .timeout)
        XCTAssertEqual(ImportFailure.map(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(ImportFailure.map(CancellationError()), .cancelled)
        XCTAssertFalse(ImportFailure.timeout.message.isEmpty)
        XCTAssertFalse(ImportFailure.timeout.message.contains("NSError"))
    }

    func testSaveRequiresTitleAndDoesNotTreatDraftAsRecipe() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        var document = RecipeImportDocument.emptyManual()
        document.instructions = [ImportedInstruction(text: "Pişir.")]
        let blocked = RecipeImportService.saveDecision(document)
        XCTAssertFalse(blocked.canSave)
        XCTAssertTrue(blocked.blockers.contains(.missingTitle))

        document.title = "Elle çorba"
        document.confirmedMissingIngredients = true
        XCTAssertTrue(RecipeImportService.saveDecision(document).canSave)
        let draft = try RecipeImportService.saveDraft(document, state: .incomplete, in: context)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertTrue(recipes.isEmpty)
        XCTAssertEqual(RecipeImportService.document(from: draft)?.title, "Elle çorba")

        let saved = try RecipeImportService.save(document, in: context)
        let stored = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(stored.map(\.slug), [saved.slug])
        XCTAssertEqual(stored[0].origin, .manual)
        XCTAssertEqual(stored[0].importStatus, .ready)
        XCTAssertFalse(stored[0].requiresReview)
        XCTAssertTrue(stored[0].timeIsUnknown)
        XCTAssertEqual(stored[0].sourceProvider, "manual")
        XCTAssertFalse(stored[0].sourceAttribution.contains("MealRoutine (özgün"))
        let memory = try context.fetch(FetchDescriptor<MealMemory>()).first { $0.recipeSlug == saved.slug }
        XCTAssertEqual(memory?.timesCooked, 0)
        XCTAssertEqual(memory?.isFavorite, false)
        XCTAssertTrue(ImportedRecipeEligibility.allowsPlanning(stored[0]))
        stored[0].confirmedMissingIngredients = false
        XCTAssertFalse(ImportedRecipeEligibility.allowsPlanning(stored[0]))
    }

    func testDuplicateURLAndReimportKeepsUnselectedEdits() {
        let incoming = sampleDocument(title: "Yeni ad", ingredient: "un")
        var current = incoming
        current.title = "Eski ad"
        current.isUserEdited = true
        let kept = current.applying(incoming, fields: [.ingredients])
        XCTAssertEqual(kept.title, "Eski ad")
        XCTAssertEqual(kept.ingredients.map(\.name), ["un"])

        let existing = RecipeDuplicateInput(
            slug: "imp-1",
            title: "Çorba",
            sourceURL: "https://example.com/corba?utm_source=x",
            sourceKey: "",
            ingredientNames: ["mercimek"],
            isUserEdited: true,
            origin: .imported
        )
        var document = sampleDocument(title: "Başka", ingredient: "un")
        document.sourceURL = "https://www.example.com/corba"
        let matches = RecipeDuplicateService.matches(for: document, among: [existing])
        XCTAssertEqual(matches.first?.strength, .strong)
        XCTAssertTrue(matches.first?.isUserEdited == true)

        let unrelated = sampleDocument(title: "Karnıyarık", ingredient: "patlıcan")
        XCTAssertTrue(RecipeDuplicateService.matches(for: unrelated, among: [existing]).isEmpty)
    }

    func testGroceryKeepsUncertaintyAndSkipsUnstructuredLines() {
        let salt = IngredientLine(
            ingredientId: "import:tuz",
            nameEN: "",
            nameTR: "Tuz",
            quantity: nil,
            unit: "",
            scaling: "fixed",
            note: "",
            trAliasCurated: false,
            sortIndex: 0
        )
        salt.isUncertain = true
        let optional = IngredientLine(
            ingredientId: "import:maydanoz",
            nameEN: "",
            nameTR: "Maydanoz",
            quantity: 1,
            unit: "bunch",
            scaling: "fixed",
            note: "",
            trAliasCurated: false,
            sortIndex: 1
        )
        optional.isOptional = true
        let blocked = IngredientLine(
            ingredientId: "import:line",
            nameEN: "",
            nameTR: "",
            quantity: nil,
            unit: "",
            scaling: "fixed",
            note: "",
            trAliasCurated: false,
            sortIndex: 2
        )
        blocked.includeInGrocery = false
        blocked.originalText = "???"

        let saltLine = ImportedGrocery.sourceLine(for: salt)
        XCTAssertNil(saltLine?.quantity)
        XCTAssertEqual(saltLine?.nameTR, "Tuz")
        XCTAssertEqual(ImportedGrocery.sourceLine(for: optional)?.ingredientId, "import:maydanoz|optional")
        XCTAssertNil(ImportedGrocery.sourceLine(for: blocked))

        let merged = GroceryMerger.merge([
            GrocerySourceLine(ingredientId: "import:domates", nameTR: "Domates", nameEN: "", quantity: nil, unit: "piece"),
            GrocerySourceLine(ingredientId: "import:domates", nameTR: "Domates", nameEN: "", quantity: 2, unit: "piece"),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].quantity, 2)
    }

    func testImportInterestDoesNotOutrankExplicitLoveAndUnknownTimeIsIneligible() {
        var imported = TestFixtures.candidate("imp", score: 60, minutes: 40)
        imported.importInterest = true
        let bundled = TestFixtures.candidate("cat", score: 60, minutes: 40)
        let prefs = TestFixtures.prefs()
        let candidates = [imported, bundled]
        let importedScore = PersonalizedScoringService.score(
            imported,
            memories: [:],
            candidates: candidates,
            preferences: prefs,
            anchors: [],
            dayOffset: 0,
            now: TestFixtures.now
        )
        let bundledScore = PersonalizedScoringService.score(
            bundled,
            memories: [:],
            candidates: candidates,
            preferences: prefs,
            anchors: [],
            dayOffset: 0,
            now: TestFixtures.now
        )
        XCTAssertEqual(importedScore.final - bundledScore.final, 1)

        var loved = MealMemorySnapshot(recipeID: "cat")
        MealMemoryReducer.apply(event: .loved, at: TestFixtures.now, to: &loved)
        var fresh = MealMemorySnapshot(recipeID: "imp")
        MealMemoryReducer.apply(event: .imported, at: TestFixtures.now, to: &fresh)
        XCTAssertEqual(fresh.timesCooked, 0)
        XCTAssertFalse(fresh.isFavorite)
        XCTAssertEqual(fresh.lovedCount, 0)
        MealMemoryReducer.apply(event: .edited, at: TestFixtures.now, to: &fresh)
        XCTAssertEqual(fresh.lovedCount, 0)
        let lovedScore = PersonalizedScoringService.score(
            bundled,
            memories: ["cat": loved, "imp": fresh],
            candidates: candidates,
            preferences: prefs,
            anchors: [],
            dayOffset: 0,
            now: TestFixtures.now
        )
        XCTAssertGreaterThan(lovedScore.final, importedScore.final)

        var unknown = TestFixtures.candidate("slow", minutes: 20)
        unknown.timeIsUnknown = true
        XCTAssertFalse(PersonalizedScoringService.isEligible(
            unknown,
            preferences: prefs,
            memory: nil,
            blockedSlugs: []
        ))
    }

    func testCatalogGuardLeavesImportsOutOfBundledCount() {
        XCTAssertTrue(CatalogRecipeGuard.isBundled(originRaw: ""))
        XCTAssertTrue(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.builtIn.rawValue))
        XCTAssertFalse(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.imported.rawValue))
        XCTAssertFalse(CatalogRecipeGuard.isBundled(originRaw: RecipeOrigin.manual.rawValue))
    }

    func testLibrarySearchIncludesSourceAndSortsImports() {
        let imported = RecipeBrowseItem(
            slug: "imp",
            displayName: "Çorba",
            nameEN: "",
            country: "Türk",
            totalMinutes: 30,
            protein: "",
            diets: [],
            tags: [],
            isLoved: false,
            origin: RecipeOrigin.imported.rawValue,
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
            [bundled, imported],
            query: RecipeBrowseQuery(searchText: "mercimek", library: .imported)
        )
        XCTAssertEqual(found.map(\.slug), ["imp"])
        let sorted = RecipeBrowse.filter(
            [bundled, imported],
            query: RecipeBrowseQuery(sort: .recentlyAdded)
        )
        XCTAssertEqual(sorted.first?.slug, "imp")
    }

    private func sampleDocument(title: String, ingredient: String) -> RecipeImportDocument {
        var document = RecipeImportDocument.emptyManual()
        document.title = title
        document.origin = .imported
        document.ingredients = [ImportedIngredient(name: ingredient, quantity: 1, unit: "piece", originalText: ingredient)]
        document.instructions = [ImportedInstruction(text: "Pişir.")]
        document.totalMinutes = 30
        document.servings = 2
        return document
    }
}
