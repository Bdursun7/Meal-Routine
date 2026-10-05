import Foundation
#if canImport(CloudKit)
import CloudKit

/// CloudKit is the shared store. The private zone holds the owner's board.
/// A CKShare lets the second member read and write it. Invite codes live in the
/// public database so the partner can find the share before they are a member.
enum CloudKitHouseholdTransport {
    static let containerIdentifier = "iCloud.com.mealroutine.app"
    static let zoneName = "MealRoutineHousehold"
    static let boardType = "HouseholdBoard"
    static let lookupType = "HouseholdInviteLookup"

    static func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        guard let household = snapshot.household else { return snapshot }
        let database = try await privateDatabase()
        let zoneID = try await ensureZone(in: database)
        let recordID = CKRecord.ID(recordName: household.id.uuidString, zoneID: zoneID)
        let existing = try? await database.record(for: recordID)
        let record = existing ?? CKRecord(recordType: boardType, recordID: recordID)
        record["payload"] = try json(snapshot) as NSString
        record["revision"] = NSNumber(value: snapshot.revision)
        record["householdName"] = household.name as NSString
        do {
            try await save([record], in: database, policy: .ifServerRecordUnchanged)
        } catch {
            if let server = serverSnapshot(from: error) {
                throw HouseholdServerConflict(server: server)
            }
            throw HouseholdError.syncFailed(error.localizedDescription)
        }
        var synced = snapshot
        HouseholdReducer.markSynced(&synced)
        return synced
    }

    static func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        let database = try await privateDatabase()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: householdId.uuidString, zoneID: zoneID)
        do {
            let record = try await database.record(for: recordID)
            return try snapshot(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        let container = CKContainer(identifier: containerIdentifier)
        _ = try await requireAccount(container)
        let metadata = try await container.shareMetadata(for: url)
        let record = try await container.sharedCloudDatabase.record(for: metadata.rootRecordID)
        return try snapshot(from: record)
    }

    static func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        guard let household = snapshot.household else { return nil }
        let database = try await privateDatabase()
        let zoneID = try await ensureZone(in: database)
        let rootID = CKRecord.ID(recordName: household.id.uuidString, zoneID: zoneID)
        let root = (try? await database.record(for: rootID)) ?? CKRecord(recordType: boardType, recordID: rootID)
        root["payload"] = try json(snapshot) as NSString
        root["revision"] = NSNumber(value: snapshot.revision)
        root["householdName"] = householdName as NSString
        let share: CKShare
        if let reference = root.share, let fetched = try? await database.record(for: reference.recordID), let existing = fetched as? CKShare {
            share = existing
        } else {
            share = CKShare(rootRecord: root)
            share.publicPermission = .none
        }
        share[CKShare.SystemFieldKey.title] = householdName as NSString
        try await save([root, share], in: database, policy: .changedKeys)
        guard let url = share.url else { return nil }
        let lookupID = CKRecord.ID(recordName: lookupName(invite.inviteCode))
        let publicDB = try await publicDatabase()
        let lookup = (try? await publicDB.record(for: lookupID))
            ?? CKRecord(recordType: lookupType, recordID: lookupID)
        lookup["householdId"] = household.id.uuidString as NSString
        lookup["shareURL"] = url.absoluteString as NSString
        lookup["expiresAt"] = invite.expiresAt as NSDate
        lookup["status"] = invite.status.rawValue as NSString
        try await save([lookup], in: publicDB, policy: .changedKeys)
        return url
    }

    /// Silent push only. The visible alert is built locally from the activity diff.
    static func registerChangeSubscription() async {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        let container = CKContainer(identifier: containerIdentifier)
        guard (try? await requireAccount(container)) != nil else { return }
        let databases = [
            (container.privateCloudDatabase, "private"),
            (container.sharedCloudDatabase, "shared"),
        ]
        for (database, name) in databases {
            let subscription = CKDatabaseSubscription(subscriptionID: "mealroutine-household-\(name)")
            subscription.notificationInfo = info
            _ = try? await database.save(subscription)
        }
    }

    static func lookup(code: String) async throws -> HouseholdInviteLookup {
        let normalized = HouseholdInviteCode.normalize(code)
        guard normalized.count == HouseholdInviteCode.length else { throw HouseholdError.inviteNotFound }
        let database = try await publicDatabase()
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: lookupName(normalized)))
            guard let idString = record["householdId"] as? String, let householdId = UUID(uuidString: idString) else {
                throw HouseholdError.inviteNotFound
            }
            let share = (record["shareURL"] as? String).flatMap(URL.init(string:))
            let expires = record["expiresAt"] as? Date ?? .distantPast
            let status = record["status"] as? String ?? HouseholdInviteStatus.pending.rawValue
            return HouseholdInviteLookup(householdId: householdId, shareURL: share, expiresAt: expires, status: status)
        } catch let error as CKError where error.code == .unknownItem {
            throw HouseholdError.inviteNotFound
        } catch let error as HouseholdError {
            throw error
        } catch {
            throw HouseholdError.syncFailed(error.localizedDescription)
        }
    }

    static func acceptShare(url: URL) async throws {
        let container = CKContainer(identifier: containerIdentifier)
        _ = try await requireAccount(container)
        let metadata = try await container.shareMetadata(for: url)
        if metadata.participantStatus != .accepted {
            _ = try await container.accept(metadata)
        }
    }

    static func deleteBoard(householdId: UUID) async throws {
        let database = try await privateDatabase()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: householdId.uuidString, zoneID: zoneID)
        _ = try? await database.modifyRecords(saving: [], deleting: [recordID], savePolicy: .ifServerRecordUnchanged)
    }

    private static func save(
        _ records: [CKRecord],
        in database: CKDatabase,
        policy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: policy)
        for (_, item) in result.saveResults {
            if case .failure(let error) = item {
                if let server = serverSnapshot(from: error) {
                    throw HouseholdServerConflict(server: server)
                }
                throw error
            }
        }
    }

    private static func lookupName(_ code: String) -> String {
        "invite-\(HouseholdInviteCode.normalize(code))"
    }

    private static func privateDatabase() async throws -> CKDatabase {
        let container = CKContainer(identifier: containerIdentifier)
        _ = try await requireAccount(container)
        return container.privateCloudDatabase
    }

    private static func publicDatabase() async throws -> CKDatabase {
        let container = CKContainer(identifier: containerIdentifier)
        _ = try await requireAccount(container)
        return container.publicCloudDatabase
    }

    private static func requireAccount(_ container: CKContainer) async throws -> CKAccountStatus {
        let status = try await container.accountStatus()
        guard status == .available else { throw HouseholdError.offline }
        return status
    }

    private static func ensureZone(in database: CKDatabase) async throws -> CKRecordZone.ID {
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        _ = try? await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        return zoneID
    }

    private static func json(_ snapshot: HouseholdSnapshot) throws -> String {
        let data = try HouseholdCodec.encode(snapshot)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HouseholdError.syncFailed("Plan kodlanamadı.")
        }
        return text
    }

    private static func snapshot(from record: CKRecord) throws -> HouseholdSnapshot {
        guard let text = record["payload"] as? String, let data = text.data(using: .utf8) else {
            throw HouseholdError.syncFailed("Sunucu kaydı boş.")
        }
        return try HouseholdCodec.decode(data)
    }

    private static func serverSnapshot(from error: Error) -> HouseholdSnapshot? {
        let ck = error as? CKError
        let serverRecord = ck?.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
        guard let serverRecord, let snapshot = try? snapshot(from: serverRecord) else { return nil }
        return snapshot
    }
}

/// Session-facing CloudKit store. Method bodies stay on CloudKitHouseholdTransport.
struct CloudKitHouseholdBackend: HouseholdSyncTransport {
    func push(_ snapshot: HouseholdSnapshot) async throws -> HouseholdSnapshot {
        try await CloudKitHouseholdTransport.push(snapshot)
    }

    func pull(householdId: UUID) async throws -> HouseholdSnapshot? {
        try await CloudKitHouseholdTransport.pull(householdId: householdId)
    }

    func pullShared(url: URL) async throws -> HouseholdSnapshot? {
        try await CloudKitHouseholdTransport.pullShared(url: url)
    }

    func publishInvite(
        _ invite: HouseholdInvite,
        householdName: String,
        snapshot: HouseholdSnapshot
    ) async throws -> URL? {
        try await CloudKitHouseholdTransport.publishInvite(invite, householdName: householdName, snapshot: snapshot)
    }

    func lookup(code: String) async throws -> HouseholdInviteLookup {
        try await CloudKitHouseholdTransport.lookup(code: code)
    }

    func acceptShare(url: URL) async throws {
        try await CloudKitHouseholdTransport.acceptShare(url: url)
    }

    func deleteBoard(householdId: UUID) async throws {
        try await CloudKitHouseholdTransport.deleteBoard(householdId: householdId)
    }

    func registerChangeSubscription() async {
        await CloudKitHouseholdTransport.registerChangeSubscription()
    }
}
#endif
