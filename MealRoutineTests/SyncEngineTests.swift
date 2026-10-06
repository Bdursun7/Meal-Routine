import XCTest
@testable import MealRoutine

final class SyncEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        SyncURLProtocol.handler = nil
        super.tearDown()
    }

    func testBackoffGrowsAndStaysUnderTheCap() {
        XCTAssertEqual(SyncBackoff.delay(retryCount: 0, jitterUnit: 0), 1)
        XCTAssertEqual(SyncBackoff.delay(retryCount: 1, jitterUnit: 0), 2)
        XCTAssertEqual(SyncBackoff.delay(retryCount: 2, jitterUnit: 0), 4)
        XCTAssertEqual(SyncBackoff.delay(retryCount: 3, jitterUnit: 0), 8)
        XCTAssertEqual(SyncBackoff.delay(retryCount: 10, jitterUnit: 0), 60)
        let jittered = SyncBackoff.delay(retryCount: 1, jitterUnit: 1)
        XCTAssertGreaterThan(jittered, 2)
        XCTAssertLessThanOrEqual(jittered, 60)
    }

    func testQueueKeepsTheIdempotencyKeyAcrossRetries() async {
        let original = sampleItem(status: .pending)
        let keys = KeyLog()
        let first = await SyncDrainer.drain(items: [original], online: true, now: now) { item in
            keys.add(item.idempotencyKey)
            return .retry
        }
        XCTAssertEqual(first.first?.status, .pending)
        XCTAssertEqual(first.first?.retryCount, 1)
        XCTAssertEqual(first.first?.id, original.id)
        XCTAssertFalse(SyncQueueMachine.isReady(first[0], now: now))
        let later = now.addingTimeInterval(SyncBackoff.delay(retryCount: 0, jitterUnit: 0))
        let second = await SyncDrainer.drain(items: first, online: true, now: later) { item in
            keys.add(item.idempotencyKey)
            return .applied
        }
        XCTAssertEqual(second.first?.status, .completed)
        XCTAssertEqual(keys.values, [original.idempotencyKey, original.idempotencyKey])
        XCTAssertEqual(second.first?.payload, original.payload)
    }

    func testOfflineDrainDoesNotSendAndConflictKeepsThePayload() async {
        let original = sampleItem(status: .pending)
        let calls = CallCount()
        let offline = await SyncDrainer.drain(items: [original], online: false, now: now) { _ in
            calls.increment()
            return .applied
        }
        XCTAssertEqual(offline, [original])
        XCTAssertEqual(calls.value, 0)

        let conflicted = await SyncDrainer.drain(items: [original], online: true, now: now) { _ in
            .conflict
        }
        XCTAssertEqual(conflicted.first?.status, .requiresResolution)
        XCTAssertEqual(conflicted.first?.id, original.id)
        XCTAssertEqual(conflicted.first?.payload, original.payload)
    }

    func testFailedAfterTheRetryCapAndServerMealWins() {
        var item = sampleItem(status: .pending)
        for _ in 0..<SyncQueueMachine.maxRetries {
            item = SyncQueueMachine.markSyncing(item)
            item = SyncQueueMachine.markRetry(item)
        }
        XCTAssertEqual(item.status, .failed)
        XCTAssertEqual(item.retryCount, SyncQueueMachine.maxRetries)

        let now = self.now
        let owner = HouseholdUser(id: "owner", displayName: "Ada", createdAt: now)
        var local = try! HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now)
        let mealId = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        try! HouseholdReducer.installPlan(
            snapshot: &local,
            drafts: [HouseholdMealDraft(dayOffset: 0, recipeSlug: "corba", title: "Çorba", recipeOwnerUserId: nil)],
            weekStart: now,
            actor: owner,
            now: now,
            mealIds: [mealId]
        )
        var server = local
        server.plan?.meals[0].title = "Pilav"
        server.plan?.meals[0].recipeSlug = "pilav"
        server.plan?.meals[0].revision = 4
        server.plan?.meals[0].baseRevision = 4
        local.plan?.meals[0].title = "Taslak"
        local.plan?.meals[0].revision = 2
        local.plan?.meals[0].baseRevision = 1
        let merged = HouseholdConflictResolver.merge(local: local, server: server)
        XCTAssertEqual(merged.plan?.meals.first?.title, "Pilav")
        XCTAssertTrue(SharedConflictNotice.mealOverridden(localBase: 1, localRevision: 2, serverRevision: 4))
        XCTAssertEqual(SharedConflictNotice.mealUpdated, "Bu yemek başka bir cihazda güncellendi.")
        let pending = sampleItem(status: .pending)
        let ids = BoardDeltaMerge.overriddenMealIDs(
            pending: [pending],
            remoteRevisions: [pending.entityId.lowercased(): 9]
        )
        XCTAssertEqual(ids, [pending.entityId])
    }

    func testMutationReusesTheIdempotencyKeyAndDeltaPullDecodes() async throws {
        let store = MemoryTokenStore()
        store.save(AuthTokenSet(
            accessToken: "sync-access",
            refreshToken: "sync-refresh",
            accessExpiresAt: now.addingTimeInterval(900),
            accountId: "11111111-1111-4111-8111-111111111111",
            displayName: "Ada"
        ))
        let householdId = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let keys = KeyLog()
        SyncURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            keys.addPath(path)
            if path.hasSuffix("/changes") {
                XCTAssertEqual(request.url?.query, "cursor=3")
                let body = #"{"cursor":4,"changes":[{"cursor":4,"entityType":"meal","entityId":"meal-1","operationType":"replace","revision":2}]}"#
                return Self.http(Data(body.utf8), status: 200)
            }
            keys.add(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sync-access")
            if keys.values.count == 1 {
                return Self.http(Data(#"{"error":"version_conflict","entityType":"meal","server":{"title":"Pilav"}}"#.utf8), status: 409)
            }
            let ok = #"{"cursor":4,"entityType":"grocery","entityId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","revision":1,"entity":{"quantity":1}}"#
            return Self.http(Data(ok.utf8), status: 200)
        }
        let api = makeClient(store: store)
        let body = BoardMutationEncoder.groceryAdd(
            id: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!,
            itemKey: "sut|l",
            quantity: 1,
            baseRevision: 0
        )
        let key = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!.uuidString
        do {
            try await api.mutate(householdId: householdId, idempotencyKey: key, body: body)
            XCTFail("expected conflict")
        } catch BoardSyncFailure.conflict {
        }
        try await api.mutate(householdId: householdId, idempotencyKey: key, body: body)
        let page = try await api.changes(householdId: householdId, cursor: 3)
        XCTAssertEqual(page.cursor, 4)
        XCTAssertEqual(page.changes.first?.entityType, "meal")
        XCTAssertEqual(keys.values, [key, key])
        XCTAssertTrue(keys.paths.contains("/v1/households/\(householdId.uuidString)/mutations"))
    }

    func testFakeBackendCanSimulateOfflineWithoutDroppingTheBoard() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner", displayName: "Ada", createdAt: now)
        var snapshot = try HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now)
        snapshot = try await backend.push(snapshot)
        backend.setOffline(true)
        do {
            _ = try await backend.push(snapshot)
            XCTFail("expected offline")
        } catch HouseholdError.offline {
        }
        let pulled = try await backend.pull(householdId: try XCTUnwrap(snapshot.household?.id))
        XCTAssertEqual(pulled?.household?.name, "Ev")
        backend.setOffline(false)
        let again = try await backend.push(snapshot)
        XCTAssertEqual(again.household?.name, "Ev")
    }

    func testPendingOperationRoundTripKeepsTheSpecFields() async throws {
        let item = sampleItem(status: .pending)
        let loaded = try await MainActor.run { () throws -> [SyncWorkItem] in
            let container = try ModelContainerFactory.make(inMemory: true)
            let context = ModelContext(container)
            PendingOperationStore.upsert(item, in: context)
            return PendingOperationStore.items(in: context)
        }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].entityType, "reaction")
        XCTAssertEqual(loaded[0].entityId, item.entityId)
        XCTAssertEqual(loaded[0].operationType, "set")
        XCTAssertEqual(loaded[0].payload, item.payload)
        XCTAssertEqual(loaded[0].retryCount, 0)
        XCTAssertEqual(loaded[0].status, .pending)
    }

    private func sampleItem(status: PendingOperationStatus) -> SyncWorkItem {
        let mealId = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let payload = BoardMutationEncoder.reaction(
            mealId: UUID(uuidString: mealId)!,
            reactionBase: 0,
            mealRevision: 1,
            reaction: "veto"
        )
        return SyncWorkItem(
            id: UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!,
            entityType: "reaction",
            entityId: mealId,
            operationType: "set",
            payload: payload,
            createdAt: now,
            retryCount: 0,
            status: status
        )
    }

    private func makeClient(store: MemoryTokenStore) -> BoardSyncClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncURLProtocol.self]
        let clock = now
        let client = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: URLSession(configuration: configuration),
            tokens: store,
            now: { clock },
            refreshGate: RefreshGate(),
            expiry: SessionExpiryCenter()
        )
        return BoardSyncClient(client: client)
    }

    private static func http(_ data: Data, status: Int) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: URL(string: "http://localhost:8080")!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            data
        )
    }
}

private final class KeyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    private var recordedPaths: [String] = []

    func add(_ key: String) {
        lock.lock()
        items.append(key)
        lock.unlock()
    }

    func addPath(_ path: String) {
        lock.lock()
        recordedPaths.append(path)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }
}

private final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class SyncURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
