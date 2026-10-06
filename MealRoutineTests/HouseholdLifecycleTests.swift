import XCTest
@testable import MealRoutine

final class HouseholdLifecycleTests: XCTestCase {
    private var store: MemoryTokenStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let householdId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let otherHouseholdId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let inviteId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let accountId = "11111111-1111-1111-1111-111111111111"

    override func setUp() {
        super.setUp()
        store = MemoryTokenStore()
        store.save(AuthTokenSet(
            accessToken: "life-access",
            refreshToken: "life-refresh",
            accessExpiresAt: now.addingTimeInterval(900),
            accountId: accountId,
            displayName: "Ada"
        ))
        HouseholdLifecycleURLProtocol.handler = nil
    }

    override func tearDown() {
        HouseholdLifecycleURLProtocol.handler = nil
        store = nil
        super.tearDown()
    }

    func testReducerKeepsPersonalDataAcrossRenameTransferAndLeave() throws {
        let failures = HouseholdLogicChecks.runAll().filter { $0.hasPrefix("lifecycle edges") }
        XCTAssertEqual(failures, [])
    }

    func testMergeKeepsProjectionsUntilTheHouseholdIsGone() throws {
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        var personal = MealMemorySnapshot(recipeID: "corba")
        personal.lovedCount = 3
        var snapshot = try HouseholdReducer.createHousehold(
            user: owner,
            name: "Ev",
            now: now,
            householdId: householdId
        )
        let projection = HouseholdRecipeProjection(
            slug: "corba",
            ownerUserId: owner.id,
            title: "Çorba",
            totalMinutes: 25,
            ingredientIds: ["lentil"],
            protein: "legume",
            category: "soup",
            cuisine: "TR",
            diets: [],
            isReadyToCook: true,
            revision: 1,
            baseRevision: 0
        )
        snapshot.recipeProjections = [projection]
        let preferenceId = snapshot.preference?.id

        let renamed = HouseholdRemoteMerge.apply(
            HouseholdRemoteState(household: HouseholdRemoteBody(
                id: householdId,
                name: "Sofra",
                role: "owner",
                members: [HouseholdRemoteMember(accountId: owner.id, displayName: "Berkay", role: "owner")],
                invites: [HouseholdRemoteInvite(
                    id: inviteId,
                    code: "ABC234",
                    status: "cancelled",
                    expiresAt: now.addingTimeInterval(3_600)
                )]
            )),
            to: snapshot,
            now: now
        )
        XCTAssertEqual(renamed.household?.name, "Sofra")
        XCTAssertEqual(renamed.recipeProjections, [projection])
        XCTAssertEqual(renamed.preference?.id, preferenceId)
        XCTAssertEqual(renamed.invites.first?.status, .revoked)

        let asMember = HouseholdRemoteMerge.apply(
            HouseholdRemoteState(household: HouseholdRemoteBody(
                id: householdId,
                name: "Sofra",
                role: "member",
                members: [
                    HouseholdRemoteMember(accountId: "partner", displayName: "Ayşe", role: "owner"),
                    HouseholdRemoteMember(accountId: owner.id, displayName: "Berkay", role: "member"),
                ],
                invites: [HouseholdRemoteInvite(
                    id: inviteId,
                    code: "ABC234",
                    status: "pending",
                    expiresAt: now.addingTimeInterval(3_600)
                )]
            )),
            to: renamed,
            now: now
        )
        XCTAssertTrue(asMember.invites.isEmpty)
        XCTAssertEqual(asMember.recipeProjections, [projection])

        let cleared = HouseholdRemoteMerge.apply(HouseholdRemoteState(household: nil), to: asMember, now: now)
        XCTAssertNil(cleared.household)
        XCTAssertTrue(cleared.recipeProjections.isEmpty)
        XCTAssertNil(cleared.preference)
        XCTAssertEqual(personal.lovedCount, 3)
        XCTAssertEqual(personal.recipeID, "corba")
        XCTAssertEqual(HouseholdRemoteMerge.status("rejected"), .rejected)
        XCTAssertEqual(HouseholdRemoteMerge.status("revoked"), .revoked)
    }

    func testFakeBackendRoundTripsRenameAndTransfer() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let partner = HouseholdUser(id: "partner", displayName: "Ayşe", createdAt: now)
        var personal = MealMemorySnapshot(recipeID: "mercimek")
        personal.neverAgain = false
        var snapshot = try HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now, householdId: householdId)
        snapshot = try await backend.push(snapshot)
        try HouseholdReducer.rename(snapshot: &snapshot, userId: owner.id, name: "Sofra", now: now)
        snapshot = try await backend.push(snapshot)
        let renamed = try await backend.pull(householdId: householdId)
        XCTAssertEqual(renamed?.household?.name, "Sofra")
        XCTAssertEqual(renamed?.preference?.householdId, householdId)

        let invite = try HouseholdReducer.createInvite(snapshot: &snapshot, user: owner, now: now, seed: 21)
        snapshot = try await backend.push(snapshot)
        try HouseholdReducer.acceptInvite(snapshot: &snapshot, user: partner, code: invite.inviteCode, now: now)
        snapshot = try await backend.push(snapshot)
        try HouseholdReducer.transferOwnership(snapshot: &snapshot, actorId: owner.id, memberUserId: partner.id, now: now)
        snapshot = try await backend.push(snapshot)
        let transferred = try await backend.pull(householdId: householdId)
        XCTAssertEqual(transferred?.role(of: partner.id), .owner)
        XCTAssertEqual(transferred?.role(of: owner.id), .member)
        XCTAssertEqual(transferred?.preference?.householdId, householdId)
        XCTAssertEqual(personal.recipeID, "mercimek")
        XCTAssertFalse(personal.neverAgain)
    }

    func testLifecycleRoutesSendBearerAndMapErrors() async throws {
        let log = LifecycleRequestLog()
        HouseholdLifecycleURLProtocol.handler = { request in
            log.add(request)
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            if method == "POST", path == "/v1/households" {
                return Self.http(Self.householdJSON(name: "Sofra", invites: false), status: 200)
            }
            if method == "POST", path.hasSuffix("/invites") {
                return Self.http(Self.householdJSON(name: "Sofra", invites: true), status: 200)
            }
            if method == "POST", path.hasSuffix("/resend") || path.hasSuffix("/cancel") {
                return Self.http(Self.householdJSON(name: "Sofra", invites: path.hasSuffix("/resend")), status: 200)
            }
            if method == "GET", path == "/v1/households/current" {
                return Self.http(Self.errorJSON("not_found"), status: 404)
            }
            if method == "PATCH" {
                return Self.http(Self.errorJSON("forbidden"), status: 403)
            }
            if path.hasSuffix("/accept") {
                return Self.http(Self.errorJSON("invite_expired"), status: 409)
            }
            if path.hasSuffix("/reject") {
                return Self.http(Self.errorJSON("invite_cancelled"), status: 409)
            }
            if path.contains("/members/") || path.hasSuffix("/leave") || path.hasSuffix("/transfer") || method == "DELETE" {
                return Self.http(Self.errorJSON("forbidden"), status: 403)
            }
            return Self.http(Self.errorJSON("duplicate_invite"), status: 409)
        }

        let api = makeAPI()
        let created = try await api.create(name: "Sofra")
        XCTAssertEqual(created.household?.name, "Sofra")
        let invited = try await api.createInvite(householdId: householdId)
        XCTAssertEqual(invited.household?.invites.first?.code, "ABC234")
        let resent = try await api.resendInvite(householdId: householdId, inviteId: inviteId)
        XCTAssertEqual(resent.household?.invites.first?.status, "pending")
        _ = try await api.cancelInvite(householdId: householdId, inviteId: inviteId)

        await expectHouseholdError(.notMember) { _ = try await api.current() }
        await expectHouseholdError(.notOwner) { _ = try await api.rename(householdId: otherHouseholdId, name: "Başka") }
        await expectHouseholdError(.inviteExpired) { _ = try await api.accept(code: "abc234") }
        await expectHouseholdError(.inviteRevoked) { try await api.reject(code: "abc234") }
        await expectHouseholdError(.notOwner) {
            _ = try await api.removeMember(householdId: otherHouseholdId, accountId: accountId)
        }
        await expectHouseholdError(.notOwner) { _ = try await api.leave(householdId: otherHouseholdId) }
        await expectHouseholdError(.notOwner) {
            _ = try await api.transfer(householdId: otherHouseholdId, accountId: accountId)
        }
        await expectHouseholdError(.notOwner) { _ = try await api.deleteHousehold(householdId: otherHouseholdId) }

        let fractional = """
        {"household":{"id":"\(householdId.uuidString)","name":"Kesir","role":"owner","members":[{"accountId":"\(accountId)","displayName":"Ada","role":"owner"}],"invites":[{"id":"\(inviteId.uuidString)","code":"ABC234","status":"pending","expiresAt":"2026-10-13T00:00:00.123Z"}]}}
        """
        HouseholdLifecycleURLProtocol.handler = { request in
            log.add(request)
            return Self.http(Data(fractional.utf8), status: 200)
        }
        let decoded = try await api.create(name: "Kesir")
        XCTAssertEqual(decoded.household?.invites.first?.code, "ABC234")
        XCTAssertNotNil(decoded.household?.invites.first?.expiresAt)

        XCTAssertEqual(log.methods.first, "POST")
        XCTAssertTrue(log.paths.contains("/v1/households"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(householdId.uuidString)/invites"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(householdId.uuidString)/invites/\(inviteId.uuidString)/resend"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(householdId.uuidString)/invites/\(inviteId.uuidString)/cancel"))
        XCTAssertTrue(log.paths.contains("/v1/households/current"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(otherHouseholdId.uuidString)"))
        XCTAssertTrue(log.paths.contains("/v1/invites/ABC234/accept"))
        XCTAssertTrue(log.paths.contains("/v1/invites/ABC234/reject"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(otherHouseholdId.uuidString)/members/\(accountId)"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(otherHouseholdId.uuidString)/leave"))
        XCTAssertTrue(log.paths.contains("/v1/households/\(otherHouseholdId.uuidString)/transfer"))
        XCTAssertTrue(log.authorizations.allSatisfy { $0 == "Bearer life-access" })
        XCTAssertFalse(log.authorizations.isEmpty)
    }

    private func makeAPI() -> HouseholdLifecycleAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HouseholdLifecycleURLProtocol.self]
        let clock = now
        let client = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: URLSession(configuration: configuration),
            tokens: store,
            now: { clock },
            refreshGate: RefreshGate(),
            expiry: SessionExpiryCenter()
        )
        return HouseholdLifecycleAPI(client: client)
    }

    private func expectHouseholdError(
        _ expected: HouseholdError,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("expected \(expected) got \(error)")
        }
    }

    private static func householdJSON(name: String, invites: Bool) -> Data {
        let inviteJSON = invites
            ? ",\"invites\":[{\"id\":\"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB\",\"code\":\"ABC234\",\"status\":\"pending\",\"expiresAt\":\"2026-10-13T00:00:00Z\"}]"
            : ",\"invites\":[]"
        let json = """
        {"household":{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","name":"\(name)","role":"owner","members":[{"accountId":"11111111-1111-1111-1111-111111111111","displayName":"Ada","role":"owner"}]\(inviteJSON)}}
        """
        return Data(json.utf8)
    }

    private static func errorJSON(_ code: String) -> Data {
        Data(#"{"error":"\#(code)"}"#.utf8)
    }

    private static func http(_ data: Data, status: Int) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://localhost:8080")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class LifecycleRequestLog: @unchecked Sendable {
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

    var methods: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap(\.httpMethod)
    }

    var authorizations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }
}

/// Separate from AuthTokenTests.StubURLProtocol so parallel XCTest classes do not share a handler.
final class HouseholdLifecycleURLProtocol: URLProtocol, @unchecked Sendable {
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
