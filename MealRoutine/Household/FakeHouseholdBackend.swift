import Foundation

/// Server copy of a household board kept for test mode.
/// Two local snapshots push and pull through it, including same-row conflicts.
struct FakeHouseholdBackendState: Codable, Equatable, Sendable {
    var boards: [HouseholdSnapshot]
    var lookups: [FakeInviteRecord]
    var acceptedShareURLs: [String]

    static let empty = FakeHouseholdBackendState(boards: [], lookups: [], acceptedShareURLs: [])
}

struct FakeInviteRecord: Codable, Equatable, Sendable {
    var code: String
    var householdId: UUID
    var shareURL: String?
    var expiresAt: Date
    var status: String
}

/// In-memory household server. SwiftData persistence is the session's cache of `exportState()`.
final class FakeHouseholdBackend: @unchecked Sendable, HouseholdSyncTransport {
    static let shared = FakeHouseholdBackend()

    private let lock = NSLock()
    private var boards: [UUID: HouseholdSnapshot] = [:]
    private var lookups: [String: FakeInviteRecord] = [:]
    private var acceptedShareURLs: Set<String> = []

    func reset() {
        lock.lock()
        boards = [:]
        lookups = [:]
        acceptedShareURLs = []
        lock.unlock()
    }

    func exportState() -> FakeHouseholdBackendState {
        lock.lock()
        defer { lock.unlock() }
        return FakeHouseholdBackendState(
            boards: boards.values.sorted { ($0.household?.id.uuidString ?? "") < ($1.household?.id.uuidString ?? "") },
            lookups: lookups.values.sorted { $0.code < $1.code },
            acceptedShareURLs: acceptedShareURLs.sorted()
        )
    }

    func importState(_ state: FakeHouseholdBackendState) {
        lock.lock()
        defer { lock.unlock() }
        boards = Dictionary(uniqueKeysWithValues: state.boards.compactMap { board in
            guard let id = board.household?.id else { return nil }
            return (id, board)
        })
        lookups = Dictionary(uniqueKeysWithValues: state.lookups.map { ($0.code, $0) })
        acceptedShareURLs = Set(state.acceptedShareURLs)
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(exportState())
    }

    func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        importState(try decoder.decode(FakeHouseholdBackendState.self, from: data))
    }

    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        lock.lock()
        defer { lock.unlock() }
        try pushLocked(snapshot)
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return boards[householdId]
    }

    func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard acceptedShareURLs.contains(url.absoluteString) else { throw HouseholdError.notMember }
        guard let record = lookups.values.first(where: { $0.shareURL == url.absoluteString }) else {
            throw HouseholdError.inviteNotFound
        }
        return boards[record.householdId]
    }

    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        _ = householdName
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.household != nil else { return nil }
        _ = try pushLocked(snapshot)
        let code = HouseholdInviteCode.normalize(invite.inviteCode)
        let url = Self.shareURL(for: code)
        lookups[code] = FakeInviteRecord(
            code: code,
            householdId: invite.householdId,
            shareURL: url.absoluteString,
            expiresAt: invite.expiresAt,
            status: invite.status.rawValue
        )
        return url
    }

    func lookup(code: String) async throws -> HouseholdInviteLookup {
        lock.lock()
        defer { lock.unlock() }
        let normalized = HouseholdInviteCode.normalize(code)
        guard normalized.count == HouseholdInviteCode.length else { throw HouseholdError.inviteNotFound }
        guard let record = lookups[normalized] else { throw HouseholdError.inviteNotFound }
        if let board = boards[record.householdId],
           let invite = board.invites.first(where: { HouseholdInviteCode.normalize($0.inviteCode) == normalized }) {
            return HouseholdInviteLookup(
                householdId: invite.householdId,
                shareURL: record.shareURL.flatMap(URL.init(string:)),
                expiresAt: invite.expiresAt,
                status: invite.status.rawValue
            )
        }
        return HouseholdInviteLookup(
            householdId: record.householdId,
            shareURL: record.shareURL.flatMap(URL.init(string:)),
            expiresAt: record.expiresAt,
            status: record.status
        )
    }

    func acceptShare(url: URL) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard lookups.values.contains(where: { $0.shareURL == url.absoluteString }) else {
            throw HouseholdError.inviteNotFound
        }
        acceptedShareURLs.insert(url.absoluteString)
    }

    func deleteBoard(householdId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        boards[householdId] = nil
        lookups = lookups.filter { $0.value.householdId != householdId }
    }

    func registerChangeSubscription() async {}

    static func shareURL(for code: String) -> URL {
        URL(string: "mealroutine://household/test-share?code=\(HouseholdInviteCode.normalize(code))")!
    }

    private func pushLocked(_ snapshot: HouseholdSnapshot) throws -> HouseholdSnapshot {
        guard let household = snapshot.household else { return snapshot }
        if let server = boards[household.id], snapshot.baseRevision != server.revision {
            throw HouseholdServerConflict(server: server)
        }
        var synced = snapshot
        HouseholdReducer.markSynced(&synced)
        boards[household.id] = synced
        for invite in synced.invites {
            let code = HouseholdInviteCode.normalize(invite.inviteCode)
            guard var record = lookups[code] else { continue }
            record.status = invite.status.rawValue
            record.expiresAt = invite.expiresAt
            lookups[code] = record
        }
        return synced
    }
}
