import Foundation

struct HouseholdServerConflict: Error, Sendable {
    var server: HouseholdSnapshot
}

struct HouseholdInviteLookup: Equatable, Sendable {
    var householdId: UUID
    var shareURL: URL?
    var expiresAt: Date
    var status: String
}

/// Shared store behind HouseholdSession. CloudKit is one implementation.
/// Test mode uses the in-memory fake. The session does not call the store directly.
protocol HouseholdSyncTransport: Sendable {
    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot
    func pull(householdId: UUID) async throws -> HouseholdSnapshot?
    func pullShared(url: URL) async throws -> HouseholdSnapshot?
    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL?
    func lookup(code: String) async throws -> HouseholdInviteLookup
    func acceptShare(url: URL) async throws
    func deleteBoard(householdId: UUID) async throws
    func registerChangeSubscription() async
}

/// No network. Used when this build cannot sign iCloud, or CloudKit is unavailable.
struct OfflineHouseholdTransport: HouseholdSyncTransport {
    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        throw HouseholdError.offline
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        throw HouseholdError.offline
    }

    func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        throw HouseholdError.offline
    }

    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        throw HouseholdError.offline
    }

    func lookup(code: String) async throws -> HouseholdInviteLookup {
        throw HouseholdError.offline
    }

    func acceptShare(url: URL) async throws {
        throw HouseholdError.offline
    }

    func deleteBoard(householdId: UUID) async throws {}

    func registerChangeSubscription() async {}
}

enum HouseholdSyncRouting {
    /// Test mode stays on the in-memory fake. Every other launch talks to the
    /// MealRoutine API when a base URL is configured. CloudKit remains available
    /// for a build that has no API address.
    static func makeTransport(testMode: Bool) -> any HouseholdSyncTransport {
        if testMode {
            return FakeHouseholdBackend.shared
        }
        if let baseURL = MealRoutineConfig.apiBaseURL {
            return HTTPHouseholdTransport(baseURL: baseURL)
        }
        #if HOUSEHOLD_LOCAL
        return OfflineHouseholdTransport()
        #else
        #if canImport(CloudKit)
        return CloudKitHouseholdBackend()
        #else
        return OfflineHouseholdTransport()
        #endif
        #endif
    }
}
