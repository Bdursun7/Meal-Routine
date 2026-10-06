import Foundation

/// Talks to the MealRoutine API. SwiftData stays the local cache; this is the server side.
struct HTTPHouseholdTransport: HouseholdSyncTransport {
    var client: APIClient

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokens: any TokenStoring = AuthServices.sharedTokens,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshGate: RefreshGate = AuthServices.refreshGate,
        expiry: SessionExpiryCenter = AuthServices.expiry
    ) {
        client = APIClient(
            baseURL: baseURL,
            session: session,
            tokens: tokens,
            now: now,
            refreshGate: refreshGate,
            expiry: expiry
        )
    }

    init(client: APIClient) {
        self.client = client
    }

    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        guard let householdId = snapshot.household?.id else {
            throw HouseholdError.syncFailed("Ev halkı yok.")
        }
        let body = try HouseholdCodec.encode(snapshot)
        let (data, http) = try await send(
            method: "PUT",
            path: "/v1/households/\(householdId.uuidString)/board",
            body: body
        )
        if http.statusCode == 409, let server = try? HouseholdCodec.decode(data) {
            throw HouseholdServerConflict(server: server)
        }
        try accept(http)
        return try HouseholdCodec.decode(data)
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        let (data, http) = try await send(
            method: "GET",
            path: "/v1/households/\(householdId.uuidString)/board",
            body: nil
        )
        if http.statusCode == 404 { return nil }
        try accept(http)
        return try HouseholdCodec.decode(data)
    }

    func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let (data, http) = try await send(method: "GET", path: "/v1/shares/board?url=\(encoded)", body: nil)
        if http.statusCode == 404 { return nil }
        try accept(http)
        return try HouseholdCodec.decode(data)
    }

    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        let body = try JSONEncoder().encode(PublishInviteBody(inviteCode: invite.inviteCode, householdName: householdName))
        let (data, http) = try await send(
            method: "POST",
            path: "/v1/households/\(invite.householdId.uuidString)/invites",
            body: body
        )
        try accept(http)
        let decoded = try JSONDecoder().decode(PublishInviteResponse.self, from: data)
        guard let raw = decoded.shareURL, let url = URL(string: raw) else { return nil }
        return url
    }

    func lookup(code: String) async throws -> HouseholdInviteLookup {
        let (data, http) = try await send(method: "GET", path: "/v1/invites/\(code)", body: nil)
        if http.statusCode == 404 { throw HouseholdError.inviteNotFound }
        try accept(http)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(InviteLookupDTO.self, from: data)
        return HouseholdInviteLookup(
            householdId: dto.householdId,
            shareURL: dto.shareURL.flatMap(URL.init(string:)),
            expiresAt: dto.expiresAt,
            status: dto.status
        )
    }

    func acceptShare(url: URL) async throws {
        let body = try JSONEncoder().encode(ShareURLBody(url: url.absoluteString))
        let (_, http) = try await send(method: "POST", path: "/v1/shares/accept", body: body)
        try accept(http)
    }

    func deleteBoard(householdId: UUID) async throws {
        let (_, http) = try await send(method: "DELETE", path: "/v1/households/\(householdId.uuidString)", body: nil)
        if http.statusCode == 404 { return }
        try accept(http)
    }

    func registerChangeSubscription() async {}

    private func send(method: String, path: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await client.request(method: method, path: path, body: body, authenticated: true)
        } catch AuthAPIError.sessionExpired {
            throw HouseholdError.sessionExpired
        } catch AuthAPIError.transport {
            throw HouseholdError.offline
        }
    }

    private func accept(_ http: HTTPURLResponse) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw HouseholdError.sessionExpired
        case 403:
            throw HouseholdError.notMember
        case 404:
            throw HouseholdError.inviteNotFound
        default:
            throw HouseholdError.syncFailed("Sunucu \(http.statusCode) döndü.")
        }
    }
}

/// Account calls and the household transport share one token store.
struct HouseholdRepository {
    var transport: any HouseholdSyncTransport

    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        try await transport.push(snapshot)
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        try await transport.pull(householdId: householdId)
    }
}

private struct PublishInviteBody: Encodable {
    var inviteCode: String
    var householdName: String
}

private struct PublishInviteResponse: Decodable {
    var shareURL: String?
}

private struct ShareURLBody: Encodable {
    var url: String
}

private struct InviteLookupDTO: Decodable {
    var householdId: UUID
    var shareURL: String?
    var expiresAt: Date
    var status: String
}
