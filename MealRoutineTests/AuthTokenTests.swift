import XCTest
@testable import MealRoutine

final class AuthTokenTests: XCTestCase {
    private var store: MemoryTokenStore!
    private var expiry: SessionExpiryCenter!
    private var now: Date!

    override func setUp() {
        super.setUp()
        store = MemoryTokenStore()
        expiry = SessionExpiryCenter()
        now = Date(timeIntervalSince1970: 1_800_000_000)
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testRefreshPolicyUsesASkewWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(TokenRefreshPolicy.needsRefresh(accessExpiresAt: now.addingTimeInterval(30), now: now))
        XCTAssertTrue(TokenRefreshPolicy.needsRefresh(accessExpiresAt: now, now: now))
        XCTAssertFalse(TokenRefreshPolicy.needsRefresh(accessExpiresAt: now.addingTimeInterval(120), now: now))
    }

    func testMemoryStoreRoundTrip() {
        let tokens = sampleTokens(access: "access", refresh: "refresh", expiresIn: 600)
        XCTAssertNil(store.load())
        store.save(tokens)
        XCTAssertEqual(store.load(), tokens)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testKeychainStoreRoundTrip() {
        let keychain = KeychainTokenStore(service: "com.mealroutine.app.auth.tests.\(UUID().uuidString)")
        let tokens = sampleTokens(access: "access-keychain", refresh: "refresh-keychain", expiresIn: 600)
        keychain.clear()
        XCTAssertNil(keychain.load())
        keychain.save(tokens)
        XCTAssertEqual(keychain.load()?.accessToken, tokens.accessToken)
        XCTAssertEqual(keychain.load()?.refreshToken, tokens.refreshToken)
        XCTAssertEqual(keychain.load()?.accountId, tokens.accountId)
        keychain.save(sampleTokens(access: "next", refresh: "next-refresh", expiresIn: 600))
        XCTAssertEqual(keychain.load()?.accessToken, "next")
        keychain.clear()
        XCTAssertNil(keychain.load())
    }

    func testDevSubjectStaysStable() {
        let suite = "mealroutine.devsubject.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removeObject(forKey: "mealroutine.devSubject")
        let first = DevSubjectStore.subject(defaults: defaults)
        let second = DevSubjectStore.subject(defaults: defaults)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("dev-"))
        defaults.removeObject(forKey: "mealroutine.devSubject")
    }

    func testAPIBaseURLJoinsPaths() throws {
        let base = try XCTUnwrap(URL(string: "http://localhost:8080"))
        let url = try XCTUnwrap(APIClient.url(baseURL: base, path: "/v1/auth/refresh"))
        XCTAssertEqual(url.absoluteString, "http://localhost:8080/v1/auth/refresh")
    }

    func testExpiredAccessTokenRefreshesBeforeTheCall() async throws {
        store.save(sampleTokens(access: "old-access", refresh: "old-refresh", expiresIn: -120))
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.add(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/v1/auth/refresh") {
                return Self.json(Self.sessionJSON(access: "new-access", refresh: "new-refresh"), status: 200)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return Self.json(Data("{}".utf8), status: 200)
        }
        let (data, response) = try await client().request(
            method: "GET",
            path: "/v1/auth/me",
            body: nil,
            authenticated: true
        )
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(store.load()?.accessToken, "new-access")
        XCTAssertEqual(store.load()?.refreshToken, "new-refresh")
        let paths = requests.paths
        XCTAssertEqual(paths.first, "/v1/auth/refresh")
        XCTAssertTrue(paths.contains("/v1/auth/me"))
    }

    func testUnauthorizedCallRefreshesOnceAndRetries() async throws {
        store.save(sampleTokens(access: "stale", refresh: "refresh-1", expiresIn: 900))
        let boardHits = HitCount()
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/v1/auth/refresh") {
                return Self.json(Self.sessionJSON(access: "fresh", refresh: "refresh-2"), status: 200)
            }
            let hit = boardHits.increment()
            if hit == 1 {
                return Self.json(Data(#"{"error":"session_expired"}"#.utf8), status: 401)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
            return Self.json(Data(#"{"account":{"id":"acct-1","displayName":"Ada","givenName":"Ada","familyName":""},"identities":[]}"#.utf8), status: 200)
        }
        let repository = AccountRepository(client: client())
        let me = try await repository.me()
        XCTAssertEqual(me.account.displayName, "Ada")
        XCTAssertEqual(store.load()?.accessToken, "fresh")
        XCTAssertEqual(boardHits.value, 2)
    }

    func testExportAndDeleteSendBearerAndClearTokensOnlyAfterSuccess() async throws {
        store.save(sampleTokens(access: "privacy-access", refresh: "privacy-refresh", expiresIn: 900))
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.add(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/v1/account/export") {
                return Self.json(
                    Data(#"{"account":{"id":"acct-1"},"personal":{"recipes":[{"nameTr":"Menemen"}]}}"#.utf8),
                    status: 200
                )
            }
            if request.httpMethod == "DELETE", path.hasSuffix("/v1/account") {
                return Self.json(Data(#"{"deleted":true,"household":"left"}"#.utf8), status: 200)
            }
            return Self.json(Data(#"{"error":"invalid_request"}"#.utf8), status: 404)
        }
        let repository = AccountRepository(client: client())
        let exported = try await repository.exportData()
        let exportText = String(decoding: exported, as: UTF8.self)
        XCTAssertTrue(exportText.contains("Menemen"))
        XCTAssertFalse(exportText.contains("privacy-refresh"))
        XCTAssertFalse(exportText.contains("privacy-access"))
        XCTAssertNotNil(store.load())
        let removed = try await repository.deleteAccount()
        XCTAssertEqual(removed, AccountDeletionResult(deleted: true, household: "left"))
        XCTAssertNotNil(store.load())
        AccountPrivacySession.clearTokens(store)
        XCTAssertNil(store.load())
        XCTAssertEqual(requests.paths, ["/v1/account/export", "/v1/account"])
        XCTAssertEqual(requests.methods, ["GET", "DELETE"])
        XCTAssertEqual(requests.authorizations, ["Bearer privacy-access", "Bearer privacy-access"])
        XCTAssertEqual(AccountPrivacyCopy.confirmTitle, "Hesabını silmek istiyor musun?")
        XCTAssertEqual(AccountPrivacyCopy.deleteButton, "Hesabımı sil")
        XCTAssertEqual(AccountPrivacyCopy.cancelButton, "Vazgeç")
        XCTAssertEqual(AccountPrivacyCopy.exportButton, "Verilerimi indir")
        XCTAssertTrue(AccountPrivacyCopy.deleted.contains("silindi"))
    }

    func testFailedDeleteLeavesTheTokenStoreUntouched() async throws {
        store.save(sampleTokens(access: "privacy-access", refresh: "privacy-refresh", expiresIn: 900))
        StubURLProtocol.handler = { _ in
            Self.json(Data(#"{"error":"invalid_request"}"#.utf8), status: 500)
        }
        let repository = AccountRepository(client: client())
        do {
            _ = try await repository.deleteAccount()
            XCTFail("expected the delete to fail")
        } catch {
            XCTAssertNotNil(store.load()?.refreshToken)
        }
    }

    func testProductEventsBatchOfflineAndOptOutDropsThem() async throws {
        let suite = "mealroutine.product.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer {
            Analytics.resetProductSinkForTests()
            defaults.removePersistentDomain(forName: suite)
        }
        Analytics.setProductSink { name, properties in
            ProductEventQueue.enqueue(name: name, properties: properties, defaults: defaults)
        }
        Analytics.track(.planGenerated)
        Analytics.track(.recipeQuickSaved, properties: ["title": "Menemen", "rating": "loved", "email": "ada@example.com"])
        Analytics.track(.appOpened)
        var pending = ProductEventQueue.pending(defaults: defaults)
        XCTAssertEqual(ProductEventQueue.optOutKey, "mealroutine.analyticsOptOut")
        XCTAssertEqual(DiagnosticQueue.crashOptInKey, "mealroutine.crashReportsOptIn")
        XCTAssertEqual(pending.map(\.name), ["plan_generated", "quick_save"])
        XCTAssertEqual(pending[1].properties["rating"], "loved")
        XCTAssertNil(pending[1].properties["title"])
        XCTAssertNil(pending[1].properties["email"])
        XCTAssertFalse(pending.contains { event in
            event.properties.values.contains { $0.contains("Menemen") }
        })

        for index in 0..<23 {
            ProductEventQueue.enqueue(name: "meal_cooked", id: "event-\(index)", defaults: defaults)
        }
        let batch = ProductEventQueue.nextBatch(defaults: defaults)
        XCTAssertEqual(batch.count, ProductEventQueue.batchSize)
        ProductEventQueue.markSent(batch.map(\.id), defaults: defaults)
        pending = ProductEventQueue.pending(defaults: defaults)
        XCTAssertEqual(pending.count, 5)

        ProductEventQueue.setOptedOut(true, defaults: defaults)
        XCTAssertTrue(ProductEventQueue.pending(defaults: defaults).isEmpty)
        ProductEventQueue.enqueue(name: "meal_skipped", defaults: defaults)
        XCTAssertTrue(ProductEventQueue.pending(defaults: defaults).isEmpty)
        XCTAssertFalse(DiagnosticQueue.allowsUpload(defaults: defaults))
        DiagnosticQueue.enqueue(DiagnosticReport(kind: "crash", count: 1, exceptionType: String(repeating: "A", count: 80), signal: "11"), defaults: defaults)
        XCTAssertTrue(DiagnosticQueue.pending(defaults: defaults).isEmpty)
        DiagnosticQueue.setUploadEnabled(true, defaults: defaults)
        DiagnosticQueue.enqueue(
            DiagnosticReport(kind: "crash", count: 1, exceptionType: String(repeating: "B", count: 80), signal: "11"),
            defaults: defaults
        )
        let reports = DiagnosticQueue.pending(defaults: defaults)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].exceptionType?.count, 40)
        XCTAssertEqual(reports[0].signal, "11")
        XCTAssertEqual(reports[0].kind, "crash")
        let encoded = try JSONEncoder().encode(DiagnosticBatch(reports: reports))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("stack"))
    }

    func testProductEventUploadUsesBearerAndKeepsTheBatchWhenTheServerRejectsIt() async throws {
        let suite = "mealroutine.upload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.save(sampleTokens(access: "privacy-access", refresh: "privacy-refresh", expiresIn: 900))
        ProductEventQueue.setOptedOut(false, defaults: defaults)
        ProductEventQueue.enqueue(name: "onboarding_completed", id: "11111111-1111-4111-8111-111111111111", defaults: defaults)
        ProductEventQueue.enqueue(name: "migration_done", properties: ["title": "Mantı"], id: "22222222-2222-4222-8222-222222222222", defaults: defaults)
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.add(request)
            if request.url?.path.hasSuffix("/v1/analytics/events") == true {
                return Self.json(Data(#"{"accepted":2}"#.utf8), status: 200)
            }
            return Self.json(Data(#"{"error":"invalid_request"}"#.utf8), status: 500)
        }
        let uploader = ProductEventUploader(client: client(), defaults: defaults)
        let sent = await uploader.flushEvents()
        XCTAssertEqual(sent, 2)
        XCTAssertTrue(ProductEventQueue.pending(defaults: defaults).isEmpty)
        XCTAssertEqual(requests.paths, ["/v1/analytics/events"])
        XCTAssertEqual(requests.methods, ["POST"])
        XCTAssertEqual(requests.authorizations, ["Bearer privacy-access"])
        let body = requests.bodies.first ?? ""
        XCTAssertTrue(body.contains("onboarding_completed"))
        XCTAssertTrue(body.contains("migration_done"))
        XCTAssertFalse(body.contains("Mantı"))
        XCTAssertFalse(body.contains("privacy-refresh"))

        ProductEventQueue.enqueue(name: "sync_failed", id: "33333333-3333-4333-8333-333333333333", defaults: defaults)
        StubURLProtocol.handler = { request in
            requests.add(request)
            return Self.json(Data(#"{"error":"invalid_request"}"#.utf8), status: 500)
        }
        let failed = await uploader.flushEvents()
        XCTAssertEqual(failed, 0)
        XCTAssertEqual(ProductEventQueue.pending(defaults: defaults).map(\.name), ["sync_failed"])

        DiagnosticQueue.setUploadEnabled(false, defaults: defaults)
        let disabledCount = await uploader.flushDiagnostics()
        XCTAssertEqual(disabledCount, 0)
        DiagnosticQueue.setUploadEnabled(true, defaults: defaults)
        DiagnosticQueue.enqueue(DiagnosticReport(kind: "crash", count: 1, exceptionType: "SIGSEGV", signal: "11"), defaults: defaults)
        StubURLProtocol.handler = { request in
            requests.add(request)
            XCTAssertEqual(request.url?.path, "/v1/diagnostics")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer privacy-access")
            return Self.json(Data(#"{"accepted":1}"#.utf8), status: 200)
        }
        let sentCount = await uploader.flushDiagnostics()
        XCTAssertEqual(sentCount, 1)
        XCTAssertTrue(DiagnosticQueue.pending(defaults: defaults).isEmpty)
    }

    func testGoogleSignInLinkRequiredDoesNotStoreASession() async throws {
        StubURLProtocol.handler = { _ in
            Self.json(Data(#"{"error":"link_required","existingProviders":["apple"]}"#.utf8), status: 409)
        }
        let repository = AccountRepository(client: client())
        do {
            _ = try await repository.signInWithGoogle(identityToken: "google-token")
            XCTFail("expected link required")
        } catch AuthAPIError.linkRequired(let providers) {
            XCTAssertEqual(providers, ["apple"])
        }
        XCTAssertNil(store.load())
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let clock = now ?? Date(timeIntervalSince1970: 1_800_000_000)
        return APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: URLSession(configuration: configuration),
            tokens: store,
            now: { clock },
            refreshGate: RefreshGate(),
            expiry: expiry
        )
    }

    private func sampleTokens(access: String, refresh: String, expiresIn: TimeInterval) -> AuthTokenSet {
        AuthTokenSet(
            accessToken: access,
            refreshToken: refresh,
            accessExpiresAt: now.addingTimeInterval(expiresIn),
            accountId: "acct-1",
            displayName: "Ada"
        )
    }

    private static func sessionJSON(access: String, refresh: String) -> Data {
        let json = """
        {"accessToken":"\(access)","refreshToken":"\(refresh)","expiresIn":900,"account":{"id":"acct-1","displayName":"Ada","givenName":"Ada","familyName":""},"identities":[{"provider":"apple","email":null,"isPrivateRelay":true}]}
        """
        return Data(json.utf8)
    }

    private static func json(_ data: Data, status: Int) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:8080")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

extension AuthTokenTests {
    func testPullSendsBearerTokenAndDecodesTheBoard() async throws {
        let store = MemoryTokenStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(AuthTokenSet(
            accessToken: "board-access",
            refreshToken: "board-refresh",
            accessExpiresAt: now.addingTimeInterval(900),
            accountId: "owner",
            displayName: "Ada"
        ))
        let user = HouseholdUser(id: "owner", displayName: "Ada", createdAt: now)
        let snapshot = try HouseholdReducer.createHousehold(user: user, name: "Ev", now: now)
        let encoded = try HouseholdCodec.encode(snapshot)
        let requests = RequestLog()
        StubURLProtocol.handler = { request in
            requests.add(request)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                encoded
            )
        }
        let transport = makeTransport(store: store, now: now)
        let householdId = try XCTUnwrap(snapshot.household?.id)
        let pulled = try await transport.pull(householdId: householdId)
        XCTAssertEqual(pulled?.household?.name, "Ev")
        XCTAssertEqual(requests.paths.first, "/v1/households/\(householdId.uuidString)/board")
        XCTAssertEqual(requests.authorizations.first, "Bearer board-access")
    }

    func testForbiddenHouseholdIsNotAMember() async throws {
        let store = MemoryTokenStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(AuthTokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: now.addingTimeInterval(900),
            accountId: "stranger",
            displayName: "Bea"
        ))
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"not_found"}"#.utf8)
            )
        }
        let transport = makeTransport(store: store, now: now)
        do {
            _ = try await transport.pull(householdId: UUID())
            XCTFail("expected not a member")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, .notMember)
        }
    }

    func testPushConflictReturnsTheServerBoard() async throws {
        let store = MemoryTokenStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(AuthTokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            accessExpiresAt: now.addingTimeInterval(900),
            accountId: "owner",
            displayName: "Ada"
        ))
        let user = HouseholdUser(id: "owner", displayName: "Ada", createdAt: now)
        let snapshot = try HouseholdReducer.createHousehold(user: user, name: "Ev", now: now)
        let server = try HouseholdCodec.encode(snapshot)
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
                server
            )
        }
        let transport = makeTransport(store: store, now: now)
        do {
            _ = try await transport.push(snapshot)
            XCTFail("expected conflict")
        } catch let conflict as HouseholdServerConflict {
            XCTAssertEqual(conflict.server.household?.name, "Ev")
        }
    }

    private func makeTransport(store: MemoryTokenStore, now: Date) -> HTTPHouseholdTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: URLSession(configuration: configuration),
            tokens: store,
            now: { now },
            refreshGate: RefreshGate(),
            expiry: SessionExpiryCenter()
        )
        return HTTPHouseholdTransport(client: client)
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLRequest] = []

    func add(_ request: URLRequest) {
        lock.lock()
        items.append(request)
        lock.unlock()
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { $0.url?.path }
    }

    var authorizations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    var methods: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { $0.httpMethod }
    }

    var bodies: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.map { request in
            if let body = request.httpBody {
                return String(decoding: body, as: UTF8.self)
            }
            guard let stream = request.httpBodyStream else { return "" }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private final class HitCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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
