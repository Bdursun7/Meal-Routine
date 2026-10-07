import SwiftData
import XCTest
@testable import MealRoutine

/// Pantry behaviour that needs the app target: SwiftData cache, sync queue, planner wiring.
/// Pure rules live in `PantryDomainTests`.
@MainActor
final class PantryTests: XCTestCase {
    private var container: ModelContainer!
    private var previousAccount: HouseholdUser?
    private var previousSnapshot = HouseholdSnapshot.empty()

    override func setUp() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        previousAccount = HouseholdSession.shared.account
        previousSnapshot = HouseholdSession.shared.snapshot
        HouseholdSession.shared.account = nil
        HouseholdSession.shared.snapshot = .empty()
        GroceryListService.discardRebuildCache()
    }

    override func tearDown() async throws {
        HouseholdSession.shared.account = previousAccount
        HouseholdSession.shared.snapshot = previousSnapshot
        GroceryListService.discardRebuildCache()
        container = nil
    }

    private func remote(_ id: UUID = UUID(), household: UUID, quantity: Double, unit: String = "g", version: Int = 1) -> PantryRemoteItem {
        PantryRemoteItem(
            id: id, householdId: household, ingredientId: "tomato", displayName: "Domates", quantity: quantity, unit: unit,
            location: .pantry, minimumQuantity: nil, dateType: nil, dateValue: nil, version: version
        )
    }

    private func queue(_ payload: PantryQueuedPayload, entity: UUID, status: PendingOperationStatus, in context: ModelContext) {
        PendingOperationStore.upsert(
            SyncWorkItem(
                id: UUID(), entityType: PantrySync.entityType, entityId: entity.uuidString.lowercased(), operationType: payload.action,
                payload: PantrySync.encode(payload)!, createdAt: .now, retryCount: 0, status: status
            ),
            in: context
        )
    }

    func testPantryFormLoadsStoredQuantityAndDoesNotTreatBlankAsZero() {
        let draft = PantryFormDraft.loaded(ingredientId: "flour", name: "Un", quantity: 500, unit: "g", location: .pantry, minimumQuantity: 100)
        XCTAssertEqual(draft.quantityText, "500")
        XCTAssertEqual(draft.quantityToSave, 500)
        XCTAssertEqual(draft.minimumText, "100")
        XCTAssertTrue(draft.canSave)
        XCTAssertNil(draft.legacyUnit)
        XCTAssertEqual(draft.unit, "g")

        var cleared = draft
        cleared.quantityText = ""
        XCTAssertNil(cleared.quantityToSave)
        XCTAssertFalse(cleared.canSave)
        cleared.quantityText = "0"
        XCTAssertEqual(cleared.quantityToSave, 0)
        XCTAssertTrue(cleared.canSave)
    }

    func testBundledDictionaryIsTheAppResource() {
        XCTAssertGreaterThan(IngredientDictionary.shared.entries.count, 300)
        XCTAssertEqual(IngredientDictionary.shared.canonicalId("tomatoes"), "tomato")
    }

    func testRejectedSendsBecomeFailedInsteadOfRetryingForever() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = SyncWorkItem(id: UUID(), entityType: "pantry", entityId: UUID().uuidString, operationType: "create", payload: Data(), createdAt: now, retryCount: 0, status: .pending)
        var sent = 0
        let drained = await SyncDrainer.drain(items: [item], online: true, now: now) { _ in
            sent += 1
            return .rejected
        }
        XCTAssertEqual(drained.first?.status, .failed)
        let again = await SyncDrainer.drain(items: drained, online: true, now: now.addingTimeInterval(600)) { _ in
            sent += 1
            return .applied
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(again.first?.status, .failed)
    }

    func testPantryConflictIsKeptAndAReconnectSendsThePendingOpOnce() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = SyncWorkItem(id: UUID(), entityType: "pantry", entityId: UUID().uuidString, operationType: "update", payload: Data(), createdAt: now, retryCount: 0, status: .pending)
        var sent = 0
        let offline = await SyncDrainer.drain(items: [item], online: false, now: now) { _ in
            sent += 1
            return .applied
        }
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(offline.first?.status, .pending)
        let conflict = await SyncDrainer.drain(items: offline, online: true, now: now) { _ in
            sent += 1
            return .conflict
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(conflict.first?.status, .requiresResolution)
        let replay = await SyncDrainer.drain(items: conflict, online: true, now: now.addingTimeInterval(30)) { _ in
            sent += 1
            return .applied
        }
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(replay.first?.status, .requiresResolution)
    }

    func testServerPullReplacesTheCacheButKeepsRowsWithQueuedEdits() throws {
        let context = container.mainContext
        let household = UUID()
        let synced = PantryItem(householdID: household, ingredientID: "tomato", displayName: "Domates", quantity: 100, unit: "g")
        let edited = PantryItem(householdID: household, ingredientID: "flour", displayName: "Un", quantity: 900, unit: "g", revision: 3)
        let deletedElsewhere = PantryItem(householdID: household, ingredientID: "rice", displayName: "Pirinç", quantity: 1, unit: "kg")
        let personal = PantryItem(householdID: nil, ingredientID: "salt", displayName: "Tuz", quantity: 1, unit: "kg")
        [synced, edited, deletedElsewhere, personal].forEach(context.insert)
        try context.save()
        queue(PantryQueuedPayload(action: "update", householdID: household, item: edited.remote(householdID: household), baseVersion: 2), entity: edited.uuid, status: .pending, in: context)

        var serverEdited = remote(edited.uuid, household: household, quantity: 200, version: 2)
        serverEdited.ingredientId = "flour"
        let fresh = remote(household: household, quantity: 50, version: 1)
        PantryCache.apply(
            [remote(synced.uuid, household: household, quantity: 400, version: 2), serverEdited, fresh],
            householdID: household,
            operations: PantryOutbox.operations(in: context),
            in: context
        )

        let rows = try context.fetch(FetchDescriptor<PantryItem>())
        XCTAssertEqual(rows.first { $0.uuid == synced.uuid }?.quantity, 400)
        XCTAssertEqual(rows.first { $0.uuid == synced.uuid }?.revision, 2)
        XCTAssertEqual(rows.first { $0.uuid == edited.uuid }?.quantity, 900, "a queued edit is not silently overwritten")
        XCTAssertNil(rows.first { $0.uuid == deletedElsewhere.uuid })
        XCTAssertNotNil(rows.first { $0.uuid == fresh.id })
        XCTAssertEqual(rows.first { $0.uuid == personal.uuid }?.quantity, 1, "personal pantry never takes server rows")
    }

    func testConflictShowsTheServerRowAndBothResolutionsKeepNoSilentLoss() throws {
        let context = container.mainContext
        let household = UUID()
        let item = PantryItem(householdID: household, ingredientID: "tomato", displayName: "Domates", quantity: 300, unit: "g", revision: 3)
        context.insert(item)
        try context.save()
        let server = remote(item.uuid, household: household, quantity: 700, version: 5)
        queue(
            PantryQueuedPayload(action: "update", householdID: household, item: item.remote(householdID: household), baseVersion: 2, serverItem: server),
            entity: item.uuid, status: .requiresResolution, in: context
        )
        PantryOutbox.showServer(server, in: context)
        XCTAssertEqual(item.quantity, 700)
        XCTAssertEqual(PantryOutbox.marks(PantryOutbox.operations(in: context))[item.uuid.uuidString.lowercased()], .conflict)

        PantryOutbox.reapply(entityId: item.uuid.uuidString.lowercased(), in: context)
        XCTAssertEqual(item.quantity, 300, "reapply restores what the user saved")
        let queued = try XCTUnwrap(PantryOutbox.operations(in: context).first)
        XCTAssertEqual(queued.status, .pending)
        XCTAssertEqual(PantrySync.payload(of: queued)?.baseVersion, 5)

        var conflicted = queued
        conflicted.status = .requiresResolution
        var payload = try XCTUnwrap(PantrySync.payload(of: queued))
        payload.serverItem = server
        conflicted.payload = try XCTUnwrap(PantrySync.encode(payload))
        PendingOperationStore.replace([conflicted], in: context)
        PantryOutbox.useServer(entityId: item.uuid.uuidString.lowercased(), in: context)
        XCTAssertEqual(item.quantity, 700)
        XCTAssertTrue(PantryOutbox.operations(in: context).isEmpty)
    }

    func testTransferCopiesOnlyOnSharedIdsAndKeepsPersonalRowsOnCopy() throws {
        let context = container.mainContext
        let household = UUID()
        context.insert(PantryItem(householdID: household, ingredientID: "tomato", displayName: "Domates", quantity: 200, unit: "g"))
        context.insert(PantryItem(householdID: nil, ingredientID: "tomatoes", displayName: "Domates", quantity: 1, unit: "kg"))
        context.insert(PantryItem(householdID: nil, ingredientID: "cherry-tomato", displayName: "Cherry domates", quantity: 250, unit: "g"))
        try context.save()

        PantryTransferApply.apply(.copy, householdID: household, in: context)

        let rows = try context.fetch(FetchDescriptor<PantryItem>())
        let shared = rows.filter { $0.householdID == household }
        XCTAssertEqual(shared.first { $0.ingredientID == "tomato" }?.quantity, 1200)
        XCTAssertEqual(shared.first { $0.ingredientID == "cherry-tomato" }?.quantity, 250)
        XCTAssertEqual(shared.count, 2)
        XCTAssertEqual(rows.filter { $0.householdID == nil }.count, 2)
    }

    func testLeavingAHouseholdLeavesNoHiddenPantryCopy() throws {
        let context = container.mainContext
        let household = UUID()
        let other = UUID()
        context.insert(PantryItem(householdID: household, ingredientID: "tomato", displayName: "Domates", quantity: 1, unit: "kg"))
        context.insert(PantryItem(householdID: nil, ingredientID: "salt", displayName: "Tuz", quantity: 1, unit: "kg"))
        try context.save()
        queue(PantryQueuedPayload(action: "create", householdID: household, item: remote(household: household, quantity: 1)), entity: UUID(), status: .pending, in: context)
        queue(PantryQueuedPayload(action: "create", householdID: other, item: remote(household: other, quantity: 1)), entity: UUID(), status: .pending, in: context)

        PantryAccountPrivacy.dropHouseholdCache(householdID: household, in: context)

        let rows = try context.fetch(FetchDescriptor<PantryItem>())
        XCTAssertEqual(rows.map(\.ingredientID), ["salt"])
        XCTAssertEqual(PantryOutbox.operations(in: context).compactMap { PantrySync.payload(of: $0)?.householdID }, [other])
    }

    func testBoardDrainNeverOverwritesQueuedPantryWork() throws {
        let context = container.mainContext
        let household = UUID()
        queue(PantryQueuedPayload(action: "create", householdID: household, item: remote(household: household, quantity: 1)), entity: UUID(), status: .pending, in: context)
        let board = SyncWorkItem(id: UUID(), entityType: "meal", entityId: "m1", operationType: "replace", payload: Data(), createdAt: .now, retryCount: 0, status: .pending)
        PendingOperationStore.replace([board], keeping: PantrySync.entityType, in: context)
        let stored = PendingOperationStore.items(in: context)
        XCTAssertEqual(stored.filter(PantrySync.isPantry).count, 1)
        XCTAssertEqual(stored.filter { $0.entityType == "meal" }.count, 1)
    }

    func testDateTypeIsStoredWithItsDateAndOldRowsReadAsBestBefore() {
        let item = PantryItem(householdID: nil, ingredientID: "milk", displayName: "Süt", quantity: 1, unit: "l", dateType: .useBy, dateValue: Date())
        XCTAssertEqual(item.dateType, .useBy)
        item.setDate(nil, Date())
        XCTAssertNil(item.dateValue)
        XCTAssertNil(item.dateType)
        item.bestBefore = Date()
        item.dateTypeRaw = nil
        XCTAssertEqual(item.dateType, .bestBefore)
        let day = PantryDay.string(from: Date())
        XCTAssertEqual(item.remote(householdID: UUID()).dateValue, day)
    }

    func testPlanningAndCookingNeverChangePantryAndMarketCoverageIsIdempotent() throws {
        let context = container.mainContext
        let now = Date()
        context.insert(UserPrefs(householdSize: 2, eveningsPerWeek: 1, maxCookMinutes: 60, dislikedIngredientIds: [], hasCompletedOnboarding: true, createdAt: now))
        makeRecipe(slug: "salata", ingredientId: "tomatoes", quantity: 500, in: context)
        let stock = PantryItem(householdID: nil, ingredientID: "tomato", displayName: "Domates", quantity: 400, unit: "g")
        context.insert(stock)
        try context.save()

        let week = try WeekPlanService.replaceCurrentWeek(
            in: context,
            request: PlanRequest(householdSize: 2, evenings: 1, maxCookMinutes: 60, dislikedIngredientIds: []),
            now: now
        )
        XCTAssertEqual(stock.quantity, 400, "creating a plan does not decrement pantry")
        let meal = try XCTUnwrap(week.meals.first)
        try WeekPlanService.markCooked(uuid: meal.uuid, in: context, at: now)
        XCTAssertEqual(stock.quantity, 400, "cooking does not decrement pantry")

        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now, applyingPantry: true)
        let first = try context.fetch(FetchDescriptor<GroceryItem>()).first { $0.ingredientId == "tomatoes" }
        XCTAssertEqual(first?.quantity, 100)
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now, applyingPantry: true)
        let second = try context.fetch(FetchDescriptor<GroceryItem>()).first { $0.ingredientId == "tomatoes" }
        XCTAssertEqual(second?.quantity, 100, "a second compute does not subtract again")
        XCTAssertEqual(stock.quantity, 400, "computing the missing amount never writes stock")

        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now, applyingPantry: false)
        let full = try context.fetch(FetchDescriptor<GroceryItem>()).first { $0.ingredientId == "tomatoes" }
        XCTAssertEqual(full?.quantity, 500)
    }

    func testPlanExplanationIsUnchangedWithAnEmptyPantry() {
        let candidate = TestFixtures.candidate("soup", ingredients: ["tomato"])
        XCTAssertEqual(PantryPlanningSignal.score(candidate: candidate, stock: []), 0)
        XCTAssertNil(PantryPlanningSignal.explanation(candidate: candidate, stock: []))
        let base = PlanExplanationBuilder.noMemory
        XCTAssertEqual(PantryPlanningSignal.annotated(base, candidates: [candidate], stock: []), base)
    }

    func testPersonalPantryIsNotOfferedUntilAHouseholdExists() {
        let household = UUID()
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: nil, resolvedHouseholdId: nil))
        XCTAssertTrue(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: household, resolvedHouseholdId: nil))
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: household, resolvedHouseholdId: household.uuidString))
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 0, householdId: household, resolvedHouseholdId: nil))
        XCTAssertFalse(PantryTransferPolicy.shouldOffer(personalCount: 2, householdId: household, resolvedHouseholdId: nil, testMode: true))
    }

    private func makeRecipe(slug: String, ingredientId: String, quantity: Double, in context: ModelContext) {
        let recipe = Recipe(
            slug: slug, nameEN: slug, nameTR: slug, nativeName: "", summaryEN: "", summaryTR: "", country: "TR",
            category: "main", unitoolsCategory: "main", diets: [], difficulty: "easy", baseServings: 2,
            prepMinutes: 10, cookMinutes: 20, totalMinutes: 30, tags: [], trDogfoodScore: 50, hardIngredientPenalty: 0,
            calories: 0, protein: 0, fat: 0, carbs: 0, sourceProvider: "", sourceLicense: "", sourceAttribution: "",
            photoURL: "", photoAuthor: "", photoLicense: ""
        )
        let line = IngredientLine(
            ingredientId: ingredientId, nameEN: "Tomato", nameTR: "Domates", quantity: quantity, unit: "g",
            scaling: "fixed", note: "", trAliasCurated: false, sortIndex: 0
        )
        let step = RecipeStep(textEN: "Cook", textTR: "Pişir", minutes: nil, sortIndex: 0)
        line.recipe = recipe
        step.recipe = recipe
        recipe.ingredients = [line]
        recipe.steps = [step]
        context.insert(recipe)
        context.insert(line)
        context.insert(step)
    }
}
