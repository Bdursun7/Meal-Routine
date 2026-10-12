import Foundation

struct HouseholdRemoteState: Decodable, Equatable, Sendable {
    var household: HouseholdRemoteBody?
}

struct HouseholdRemoteBody: Decodable, Equatable, Sendable {
    var id: UUID
    var name: String
    var role: String
    var members: [HouseholdRemoteMember]
    var invites: [HouseholdRemoteInvite]
}

struct HouseholdRemoteMember: Decodable, Equatable, Sendable {
    var accountId: String
    var displayName: String
    var role: String
}

struct HouseholdRemoteInvite: Decodable, Equatable, Sendable {
    var id: UUID
    var code: String
    var status: String
    var expiresAt: Date
}

/// Authenticated household lifecycle calls. The board sync route stays separate.
struct HouseholdLifecycleAPI: Sendable {
    var client: APIClient

    func create(name: String) async throws -> HouseholdRemoteState {
        try await send(method: "POST", path: "/v1/households", body: try JSONEncoder().encode(NameBody(name: name)))
    }

    func current() async throws -> HouseholdRemoteState {
        try await send(method: "GET", path: "/v1/households/current", body: nil)
    }

    func rename(householdId: UUID, name: String) async throws -> HouseholdRemoteState {
        try await send(
            method: "PATCH",
            path: "/v1/households/\(householdId.uuidString)",
            body: try JSONEncoder().encode(NameBody(name: name))
        )
    }

    func createInvite(householdId: UUID) async throws -> HouseholdRemoteState {
        try await send(method: "POST", path: "/v1/households/\(householdId.uuidString)/invites", body: nil)
    }

    func resendInvite(householdId: UUID, inviteId: UUID) async throws -> HouseholdRemoteState {
        try await send(
            method: "POST",
            path: "/v1/households/\(householdId.uuidString)/invites/\(inviteId.uuidString)/resend",
            body: nil
        )
    }

    func cancelInvite(householdId: UUID, inviteId: UUID) async throws -> HouseholdRemoteState {
        try await send(
            method: "POST",
            path: "/v1/households/\(householdId.uuidString)/invites/\(inviteId.uuidString)/cancel",
            body: nil
        )
    }

    func accept(code: String) async throws -> HouseholdRemoteState {
        try await send(method: "POST", path: "/v1/invites/\(HouseholdInviteCode.normalize(code))/accept", body: nil)
    }

    func reject(code: String) async throws {
        let (data, http) = try await perform(method: "POST", path: "/v1/invites/\(HouseholdInviteCode.normalize(code))/reject", body: nil)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(data: data, status: http.statusCode)
        }
    }

    func removeMember(householdId: UUID, accountId: String) async throws -> HouseholdRemoteState {
        try await send(method: "DELETE", path: "/v1/households/\(householdId.uuidString)/members/\(accountId)", body: nil)
    }

    func leave(householdId: UUID) async throws -> HouseholdRemoteState {
        try await send(method: "POST", path: "/v1/households/\(householdId.uuidString)/leave", body: nil)
    }

    func transfer(householdId: UUID, accountId: String) async throws -> HouseholdRemoteState {
        try await send(
            method: "POST",
            path: "/v1/households/\(householdId.uuidString)/transfer",
            body: try JSONEncoder().encode(TransferBody(accountId: accountId))
        )
    }

    func deleteHousehold(householdId: UUID) async throws -> HouseholdRemoteState {
        try await send(method: "DELETE", path: "/v1/households/\(householdId.uuidString)", body: nil)
    }

    private func send(method: String, path: String, body: Data?) async throws -> HouseholdRemoteState {
        let (data, http) = try await perform(method: method, path: path, body: body)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(data: data, status: http.statusCode)
        }
        if data.isEmpty { return HouseholdRemoteState(household: nil) }
        return try Self.makeDecoder().decode(HouseholdRemoteState.self, from: data)
    }

    private func perform(method: String, path: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await client.request(method: method, path: path, body: body, authenticated: true)
        } catch AuthAPIError.sessionExpired {
            throw HouseholdError.sessionExpired
        } catch AuthAPIError.transport {
            throw HouseholdError.offline
        } catch {
            throw HouseholdError.offline
        }
    }

    private static func failure(data: Data, status: Int) -> HouseholdError {
        let code = (try? makeDecoder().decode(APIErrorBody.self, from: data))?.error
        switch code {
        case "already_in_household":
            return .alreadyInHousehold
        case "already_member":
            return .alreadyMember
        case "name_empty":
            return .nameEmpty
        case "not_member":
            return .notMember
        case "forbidden":
            return .notOwner
        case "household_full":
            return .householdFull
        case "duplicate_invite":
            return .duplicateInvite
        case "invite_expired":
            return .inviteExpired
        case "invite_closed":
            return .inviteClosed
        case "invite_cancelled":
            return .inviteRevoked
        case "invite_not_found":
            return .inviteNotFound
        case "not_found":
            return .notMember
        case "session_expired":
            return .sessionExpired
        default:
            if status == 401 { return .sessionExpired }
            return .syncFailed("Sunucu \(status) döndü.")
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "date")
        }
        return decoder
    }

    private static func parseDate(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}

enum HouseholdRemoteMerge {
    static func apply(_ state: HouseholdRemoteState, to snapshot: HouseholdSnapshot, now: Date) -> HouseholdSnapshot {
        guard let body = state.household else { return .empty(now: now) }
        var next = snapshot.household?.id == body.id ? snapshot : .empty(now: now)
        let ownerId = body.members.first { $0.role == "owner" }?.accountId ?? next.household?.ownerId ?? ""
        next.household = Household(
            id: body.id,
            name: body.name,
            ownerId: ownerId,
            createdAt: next.household?.createdAt ?? now,
            revision: (next.household?.revision ?? 0) + 1,
            baseRevision: next.household?.baseRevision ?? 0
        )
        next.members = body.members.map { member in
            let existing = snapshot.members.first { $0.userId == member.accountId }
            return HouseholdMember(
                id: existing?.id ?? UUID(),
                householdId: body.id,
                userId: member.accountId,
                displayName: member.displayName,
                role: member.role == "owner" ? .owner : .member,
                joinedAt: existing?.joinedAt ?? now,
                revision: (existing?.revision ?? 0) + 1,
                baseRevision: existing?.baseRevision ?? 0
            )
        }
        if body.role == "owner" {
            next.invites = body.invites.map { invite in
                let existing = snapshot.invites.first { $0.id == invite.id }
                return HouseholdInvite(
                    id: invite.id,
                    householdId: body.id,
                    createdBy: existing?.createdBy ?? ownerId,
                    inviteCode: invite.code,
                    expiresAt: invite.expiresAt,
                    status: status(invite.status),
                    shareURL: existing?.shareURL,
                    revision: (existing?.revision ?? 0) + 1,
                    baseRevision: existing?.baseRevision ?? 0
                )
            }
        } else {
            next.invites = []
        }
        next.preference = resolvedPreference(existing: next.preference, householdId: body.id)
        next.updatedAt = now
        next.revision = (next.revision) + 1
        return next
    }

    /// Keeps a preference that already belongs to this household. Otherwise uses the
    /// server board row when one was loaded, and a local default when it was not.
    static func resolvedPreference(
        existing: HouseholdPreference?,
        householdId: UUID,
        board: BoardPreferenceWire? = nil
    ) -> HouseholdPreference {
        if let existing, existing.householdId == householdId {
            return existing
        }
        if let board {
            return preference(householdId: householdId, board: board)
        }
        return HouseholdPreference(
            id: UUID(),
            householdId: householdId,
            cookingDays: [],
            maxWeekdayMinutes: 60,
            preferredCategories: [],
            preferredProteins: [],
            avoidedIngredients: [],
            revision: 1,
            baseRevision: 1
        )
    }

    /// Copies a synced board preference onto the snapshot. A local edit that has not
    /// reached the server stays put.
    static func applyBoardPreference(
        _ board: BoardPreferenceWire?,
        householdId: UUID,
        to snapshot: inout HouseholdSnapshot
    ) {
        guard let board else { return }
        guard var preference = snapshot.preference, preference.householdId == householdId else {
            snapshot.preference = preference(householdId: householdId, board: board)
            return
        }
        guard preference.revision == preference.baseRevision, board.revision >= preference.revision else { return }
        preference.cookingDays = board.cookingDays
        preference.maxWeekdayMinutes = max(15, board.maxWeekdayMinutes)
        preference.preferredCategories = board.preferredCategories
        preference.preferredProteins = board.preferredProteins
        preference.avoidedIngredients = board.avoidedIngredients
        preference.revision = board.revision
        preference.baseRevision = board.revision
        snapshot.preference = preference
    }

    private static func preference(householdId: UUID, board: BoardPreferenceWire) -> HouseholdPreference {
        HouseholdPreference(
            id: UUID(),
            householdId: householdId,
            cookingDays: board.cookingDays,
            maxWeekdayMinutes: max(15, board.maxWeekdayMinutes),
            preferredCategories: board.preferredCategories,
            preferredProteins: board.preferredProteins,
            avoidedIngredients: board.avoidedIngredients,
            revision: max(board.revision, 1),
            baseRevision: max(board.revision, 1)
        )
    }

    static func status(_ raw: String) -> HouseholdInviteStatus {
        switch raw {
        case "accepted": .accepted
        case "expired": .expired
        case "rejected": .rejected
        case "cancelled", "revoked": .revoked
        default: .pending
        }
    }
}

private struct NameBody: Encodable {
    var name: String
}

private struct TransferBody: Encodable {
    var accountId: String
}

private struct APIErrorBody: Decodable {
    var error: String
}
