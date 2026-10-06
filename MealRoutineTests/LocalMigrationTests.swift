import SwiftData
import XCTest
@testable import MealRoutine

@MainActor
final class LocalMigrationTests: XCTestCase {
    func testStateMachineReachesDoneAndRetryDoesNotDuplicate() async {
        let backend = FakeMigrationBackend()
        let center = LocalMigrationCenter(defaults: suite())
        let payload = samplePayload()

        await center.run(accountId: "account-1", payload: payload, transport: backend)
        XCTAssertEqual(center.record.phase, .done)
        XCTAssertEqual(center.record.headline, "Aktarım tamam. Yerel veriler duruyor.")
        XCTAssertEqual(backend.recipeCount, 1)
        XCTAssertEqual(backend.historyCount, 1)

        await center.run(accountId: "account-1", payload: payload, transport: backend)
        let again = try await backend.upload(payload)
        XCTAssertEqual(again.history, 1)
        XCTAssertEqual(backend.recipeCount, 1)
        XCTAssertEqual(backend.historyCount, 1)
    }

    func testResumeAfterFailureKeepsStableIds() async {
        let backend = FakeMigrationBackend()
        backend.failUploadsRemaining = 1
        let defaults = suite()
        let center = LocalMigrationCenter(defaults: defaults)
        let payload = samplePayload()

        await center.run(accountId: "account-1", payload: payload, transport: backend)
        XCTAssertEqual(center.record.phase, .failed)
        XCTAssertEqual(backend.recipeCount, 0)
        XCTAssertTrue(center.record.headline.contains("Yeniden"))

        let resumed = LocalMigrationCenter(defaults: defaults)
        await resumed.run(accountId: "account-1", payload: payload, transport: backend)
        XCTAssertEqual(resumed.record.phase, .done)
        XCTAssertEqual(resumed.record.recipes, 1)
        XCTAssertEqual(backend.recipeCount, 1)
        XCTAssertEqual(backend.historyCount, 1)
        XCTAssertEqual(payload.recipes[0].id, StableClientID.recipe(slug: "menemen").uuidString.lowercased())
    }

    func testBuiltInsAreSkippedAndLocalRowsStay() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(makeRecipe(slug: "menemen", origin: .manual, state: .savedToTry))
        context.insert(makeRecipe(slug: "mercimek", origin: .builtIn, state: .readyToCook))
        let eventID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        context.insert(MealBehaviorEvent(uuid: eventID, recipeSlug: "mercimek", eventType: .cooked))
        let memory = MealMemorySnapshot(recipeID: "mercimek", timesCooked: 2, isFavorite: true)
        context.insert(MealMemory(snapshot: memory))
        let prefs = UserPrefs()
        prefs.difficultyPreference = .openToHard
        context.insert(prefs)
        try context.save()

        let snapshot = MigrationCollector.snapshot(in: context)
        let payload = MigrationCollector.payload(
            recipes: snapshot.recipes,
            memories: snapshot.memories,
            events: snapshot.events,
            feedback: snapshot.feedback,
            prefs: snapshot.prefs
        )
        XCTAssertEqual(payload.recipes.map(\.slug), ["menemen"])
        XCTAssertEqual(payload.recipes[0].collectionState, RecipeCollectionState.savedToTry.rawValue)
        XCTAssertEqual(payload.history.map(\.id), [eventID.uuidString.lowercased()])
        XCTAssertEqual(payload.preferences?.difficultyPreference, DifficultyPreference.openToHard.rawValue)
        XCTAssertFalse(payload.favorites.isEmpty)
        XCTAssertTrue(MigrationCollector.hasEligible(
            recipes: snapshot.recipes,
            memories: snapshot.memories,
            events: snapshot.events,
            feedback: snapshot.feedback,
            prefs: snapshot.prefs
        ))

        let before = try context.fetch(FetchDescriptor<Recipe>()).count
        let backend = FakeMigrationBackend()
        let center = LocalMigrationCenter(defaults: suite())
        await center.run(accountId: "account-1", payload: payload, transport: backend)
        let after = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(after.count, before)
        XCTAssertEqual(Set(after.map(\.slug)), ["menemen", "mercimek"])
        XCTAssertEqual(backend.recipeCount, 1)
        XCTAssertEqual(backend.historyCount, 1)
    }

    func testURLProtocolSkipsBuiltInsAndResumesWithoutDuplicateHistory() async throws {
        MigrationURLProtocol.reset()
        var payload = samplePayload()
        payload.recipes.append(builtInRecipe())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MigrationURLProtocol.self]
        let client = MigrationHTTPClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://migration.test")!,
            accessToken: "token"
        )
        let center = LocalMigrationCenter(defaults: suite())
        await center.run(accountId: "account-1", payload: payload, transport: client)
        XCTAssertEqual(center.record.phase, .failed)
        await center.run(accountId: "account-1", payload: payload, transport: client)
        XCTAssertEqual(center.record.phase, .done)
        XCTAssertEqual(MigrationURLProtocol.uploadSlugs, [["menemen"], ["menemen"]])
        XCTAssertEqual(MigrationURLProtocol.historyIDs, ["dddddddd-dddd-4ddd-8ddd-dddddddddddd"])
        XCTAssertEqual(
            MigrationURLProtocol.recipeIDs,
            [StableClientID.recipe(slug: "menemen").uuidString.lowercased()]
        )
        MigrationURLProtocol.reset()
    }

    func testHouseholdStaysClosedUntilMigrationFinishes() {
        XCTAssertTrue(LocalMigrationGate.blocksHousehold(
            testMode: false,
            apiConfigured: true,
            signedIn: true,
            phase: .notStarted,
            hasEligibleData: true
        ))
        XCTAssertTrue(LocalMigrationGate.blocksHousehold(
            testMode: false,
            apiConfigured: true,
            signedIn: true,
            phase: .failed,
            hasEligibleData: true
        ))
        XCTAssertFalse(LocalMigrationGate.blocksHousehold(
            testMode: true,
            apiConfigured: true,
            signedIn: true,
            phase: .notStarted,
            hasEligibleData: true
        ))
        XCTAssertFalse(LocalMigrationGate.blocksHousehold(
            testMode: false,
            apiConfigured: true,
            signedIn: true,
            phase: .done,
            hasEligibleData: true
        ))
        XCTAssertFalse(LocalMigrationGate.blocksHousehold(
            testMode: false,
            apiConfigured: true,
            signedIn: true,
            phase: .notStarted,
            hasEligibleData: false
        ))
    }

    private func suite() -> UserDefaults {
        let name = "migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func samplePayload() -> MigrationPayload {
        let recipeID = StableClientID.recipe(slug: "menemen")
        return MigrationPayload(
            preferences: MigrationPreferencePayload(
                updatedAt: "2024-02-01T00:00:00Z",
                householdSize: 2,
                eveningsPerWeek: 5,
                maxCookMinutes: 45,
                dislikedIngredientIds: ["mushroom"],
                discoveryLevel: "balanced",
                repeatPreference: "balanced",
                difficultyPreference: "openToHard",
                weekdayStyle: "mostlyQuick",
                dismissedPatternIds: [],
                hasCompletedOnboarding: true
            ),
            recipes: [
                MigrationRecipePayload(
                    id: recipeID.uuidString.lowercased(),
                    slug: "menemen",
                    updatedAt: "2024-02-01T00:00:00Z",
                    nameTr: "Menemen",
                    nameEn: "Menemen",
                    summaryTr: "",
                    origin: "manual",
                    collectionState: "savedToTry",
                    sourceUrl: "",
                    sourceKey: "",
                    sourcePlatform: "",
                    sourceTitle: "",
                    userNotes: "",
                    baseServings: 2,
                    prepMinutes: 5,
                    cookMinutes: 10,
                    totalMinutes: 15,
                    timeIsUnknown: false,
                    servingsUnspecified: false,
                    difficulty: "easy",
                    category: "yumurta",
                    country: "TR",
                    diets: [],
                    tags: [],
                    photoUrl: "",
                    ingredients: [],
                    steps: []
                ),
            ],
            memories: [
                MigrationMemoryPayload(
                    recipeSlug: "mercimek",
                    updatedAt: "2024-02-01T00:00:00Z",
                    timesCooked: 2,
                    timesReplaced: 0,
                    timesSkipped: 0,
                    lastCookedAt: nil,
                    lastSelectedAt: nil,
                    lovedCount: 1,
                    okayCount: 0,
                    latestRating: "loved",
                    neverAgain: false,
                    timeConcernCount: 0,
                    difficultyConcernCount: 0,
                    portionConcernCount: 0,
                    missingIngredientCount: 0,
                    tooManyIngredientCount: 0,
                    wouldMakeAgainCount: 0,
                    isFavorite: true,
                    discoveryStatus: "known",
                    confidence: "high"
                ),
            ],
            favorites: [MigrationFavoritePayload(recipeSlug: "mercimek", createdAt: "2024-02-01T00:00:00Z")],
            history: [
                MigrationHistoryPayload(
                    id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
                    recipeSlug: "mercimek",
                    eventType: "cooked",
                    planWeekId: nil,
                    plannedMealId: nil,
                    replacementReason: "",
                    createdAt: "2024-02-01T00:00:00Z"
                ),
            ],
            feedback: []
        )
    }

    private func builtInRecipe() -> MigrationRecipePayload {
        var recipe = samplePayload().recipes[0]
        recipe.id = StableClientID.recipe(slug: "mercimek").uuidString.lowercased()
        recipe.slug = "mercimek"
        recipe.origin = RecipeOrigin.builtIn.rawValue
        return recipe
    }

    private func makeRecipe(slug: String, origin: RecipeOrigin, state: RecipeCollectionState) -> Recipe {
        let recipe = Recipe(
            slug: slug,
            nameEN: slug,
            nameTR: slug,
            nativeName: "",
            summaryEN: "",
            summaryTR: "",
            country: "TR",
            category: "ev",
            unitoolsCategory: "",
            diets: [],
            difficulty: "easy",
            baseServings: 2,
            prepMinutes: 5,
            cookMinutes: 10,
            totalMinutes: 15,
            tags: [],
            trDogfoodScore: 0,
            hardIngredientPenalty: 0,
            calories: 0,
            protein: 0,
            fat: 0,
            carbs: 0,
            sourceProvider: "",
            sourceLicense: "",
            sourceAttribution: "",
            photoURL: "",
            photoAuthor: "",
            photoLicense: ""
        )
        recipe.origin = origin
        recipe.collectionState = state
        recipe.savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return recipe
    }
}

private func statusJSON(status: String, counts: MigrationCounts) -> Data {
    let body: [String: Any] = [
        "status": status,
        "counts": [
            "recipes": counts.recipes,
            "memories": counts.memories,
            "favorites": counts.favorites,
            "history": counts.history,
            "feedback": counts.feedback,
        ],
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
}

private final class MigrationURLProtocol: URLProtocol {
    nonisolated(unsafe) static var uploadSlugs: [[String]] = []
    nonisolated(unsafe) static var historyIDs = Set<String>()
    nonisolated(unsafe) static var recipeIDs = Set<String>()
    nonisolated(unsafe) static var uploadAttempts = 0

    static func reset() {
        uploadSlugs = []
        historyIDs = []
        recipeIDs = []
        uploadAttempts = 0
    }

    private static func respond(_ request: URLRequest) -> (Int, Data) {
        let body = body(of: request)
        if request.url?.path == "/v1/migration/confirm" {
            let counts = MigrationCounts(recipes: 1, memories: 1, favorites: 1, history: historyIDs.count, feedback: 0)
            return (200, statusJSON(status: "confirmed", counts: counts))
        }
        uploadAttempts += 1
        if let decoded = try? JSONDecoder().decode(MigrationPayload.self, from: body) {
            uploadSlugs.append(decoded.recipes.map(\.slug))
            for recipe in decoded.recipes {
                recipeIDs.insert(recipe.id)
            }
            for event in decoded.history {
                historyIDs.insert(event.id)
            }
        }
        if uploadAttempts == 1 {
            return (500, Data("{\"error\":\"transport\"}".utf8))
        }
        let counts = MigrationCounts(recipes: 1, memories: 1, favorites: 1, history: historyIDs.count, feedback: 0)
        return (200, statusJSON(status: "uploaded", counts: counts))
    }

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = MigrationURLProtocol.respond(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://migration.test")!,
            statusCode: result.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
