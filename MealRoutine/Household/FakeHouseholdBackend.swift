import Foundation
import os

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
///
/// State sits in `OSAllocatedUnfairLock` and is touched only through `withLock`.
/// That stays synchronous, so `await` never resumes while the lock is held.
final class FakeHouseholdBackend: Sendable, HouseholdSyncTransport {
    static let shared = FakeHouseholdBackend()

    private struct Store: Sendable {
        var boards: [UUID: HouseholdSnapshot] = [:]
        var lookups: [String: FakeInviteRecord] = [:]
        var acceptedShareURLs: Set<String> = []
        var offline = false
    }

    /// Carried out of `withLock` as a `Sendable` result, then thrown.
    /// The closure itself does not throw: its result has to be `Sendable`.
    private enum LockedFailure: Error, Sendable {
        case conflict(HouseholdSnapshot)
        case notMember
        case inviteNotFound
        case offline
    }

    private let state = OSAllocatedUnfairLock(initialState: Store())

    func reset() {
        state.withLock { store in
            store = Store()
        }
    }

    func setOffline(_ offline: Bool) {
        state.withLock { store in
            store.offline = offline
        }
    }

    func exportState() -> FakeHouseholdBackendState {
        return state.withLock { store in
            FakeHouseholdBackendState(
                boards: store.boards.values.sorted { ($0.household?.id.uuidString ?? "") < ($1.household?.id.uuidString ?? "") },
                lookups: store.lookups.values.sorted { $0.code < $1.code },
                acceptedShareURLs: store.acceptedShareURLs.sorted()
            )
        }
    }

    func importState(_ imported: FakeHouseholdBackendState) {
        state.withLock { store in
            store.boards = Dictionary(uniqueKeysWithValues: imported.boards.compactMap { board in
                guard let id = board.household?.id else { return nil }
                return (id, board)
            })
            store.lookups = Dictionary(uniqueKeysWithValues: imported.lookups.map { ($0.code, $0) })
            store.acceptedShareURLs = Set(imported.acceptedShareURLs)
        }
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
        let result = state.withLock { store in
            Self.pushLocked(snapshot, into: &store)
        }
        return try Self.unwrap(result)
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        return state.withLock { store in
            store.boards[householdId]
        }
    }

    func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        let result: Result<HouseholdSnapshot?, LockedFailure> = state.withLock { store in
            guard store.acceptedShareURLs.contains(url.absoluteString) else {
                return .failure(.notMember)
            }
            guard let record = store.lookups.values.first(where: { $0.shareURL == url.absoluteString }) else {
                return .failure(.inviteNotFound)
            }
            return .success(store.boards[record.householdId])
        }
        return try Self.unwrap(result)
    }

    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        _ = householdName
        let result: Result<URL?, LockedFailure> = state.withLock { store in
            guard snapshot.household != nil else { return .success(nil) }
            switch Self.pushLocked(snapshot, into: &store) {
            case .failure(let failure):
                return .failure(failure)
            case .success:
                let code = HouseholdInviteCode.normalize(invite.inviteCode)
                let url = Self.shareURL(for: code)
                store.lookups[code] = FakeInviteRecord(
                    code: code,
                    householdId: invite.householdId,
                    shareURL: url.absoluteString,
                    expiresAt: invite.expiresAt,
                    status: invite.status.rawValue
                )
                return .success(url)
            }
        }
        return try Self.unwrap(result)
    }

    func lookup(code: String) async throws -> HouseholdInviteLookup {
        let result: Result<HouseholdInviteLookup, LockedFailure> = state.withLock { store in
            let normalized = HouseholdInviteCode.normalize(code)
            guard normalized.count == HouseholdInviteCode.length else {
                return .failure(.inviteNotFound)
            }
            guard let record = store.lookups[normalized] else {
                return .failure(.inviteNotFound)
            }
            if let board = store.boards[record.householdId],
               let invite = board.invites.first(where: { HouseholdInviteCode.normalize($0.inviteCode) == normalized }) {
                return .success(HouseholdInviteLookup(
                    householdId: invite.householdId,
                    shareURL: record.shareURL.flatMap(URL.init(string:)),
                    expiresAt: invite.expiresAt,
                    status: invite.status.rawValue
                ))
            }
            return .success(HouseholdInviteLookup(
                householdId: record.householdId,
                shareURL: record.shareURL.flatMap(URL.init(string:)),
                expiresAt: record.expiresAt,
                status: record.status
            ))
        }
        return try Self.unwrap(result)
    }

    func acceptShare(url: URL) async throws {
        let result: Result<Void, LockedFailure> = state.withLock { store in
            guard store.lookups.values.contains(where: { $0.shareURL == url.absoluteString }) else {
                return .failure(.inviteNotFound)
            }
            store.acceptedShareURLs.insert(url.absoluteString)
            return .success(())
        }
        _ = try Self.unwrap(result)
    }

    func deleteBoard(householdId: UUID) async throws {
        state.withLock { store in
            store.boards[householdId] = nil
            store.lookups = store.lookups.filter { $0.value.householdId != householdId }
        }
    }

    func registerChangeSubscription() async {}

    static func shareURL(for code: String) -> URL {
        URL(string: "mealroutine://household/test-share?code=\(HouseholdInviteCode.normalize(code))")!
    }

    private static func pushLocked(
        _ snapshot: HouseholdSnapshot,
        into store: inout Store
    ) -> Result<HouseholdSnapshot, LockedFailure> {
        if store.offline { return .failure(.offline) }
        guard let household = snapshot.household else { return .success(snapshot) }
        if let server = store.boards[household.id], snapshot.baseRevision != server.revision {
            return .failure(.conflict(server))
        }
        var synced = snapshot
        HouseholdReducer.markSynced(&synced)
        store.boards[household.id] = synced
        for invite in synced.invites {
            let code = HouseholdInviteCode.normalize(invite.inviteCode)
            guard var record = store.lookups[code] else { continue }
            record.status = invite.status.rawValue
            record.expiresAt = invite.expiresAt
            store.lookups[code] = record
        }
        return .success(synced)
    }

    private static func unwrap<T: Sendable>(_ result: Result<T, LockedFailure>) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(.conflict(let server)):
            throw HouseholdServerConflict(server: server)
        case .failure(.notMember):
            throw HouseholdError.notMember
        case .failure(.inviteNotFound):
            throw HouseholdError.inviteNotFound
        case .failure(.offline):
            throw HouseholdError.offline
        }
    }
}
