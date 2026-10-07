import Foundation
import SwiftData
#if canImport(Network)
import Network
#endif

enum PendingOperationStatus: String, Codable, Sendable, Equatable {
    case pending
    case syncing
    case completed
    case failed
    case requiresResolution
}

/// One queued shared edit. `id` is the Idempotency-Key and stays the same across retries.
struct SyncWorkItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var entityType: String
    var entityId: String
    var operationType: String
    var payload: Data
    var createdAt: Date
    var retryCount: Int
    var status: PendingOperationStatus

    var idempotencyKey: String { id.uuidString }
}

enum SyncBackoff {
    static let base: TimeInterval = 1
    static let cap: TimeInterval = 60

    /// Exponential delay plus a fraction of jitter, never above the cap.
    static func delay(retryCount: Int, jitterUnit: Double) -> TimeInterval {
        let exponential = min(cap, base * pow(2, Double(max(0, retryCount))))
        let unit = min(1, max(0, jitterUnit))
        return min(cap, exponential + (exponential * 0.25 * unit))
    }
}

enum SharedConflictNotice {
    static let mealUpdated = "Bu yemek başka bir cihazda güncellendi."

    /// The server moved the meal after this device started editing it.
    static func mealOverridden(localBase: Int, localRevision: Int, serverRevision: Int) -> Bool {
        localRevision != localBase && serverRevision != localBase
    }
}

enum SyncQueueMachine {
    static let maxRetries = 5

    static func markSyncing(_ item: SyncWorkItem) -> SyncWorkItem {
        var copy = item
        guard copy.status == .pending else { return copy }
        copy.status = .syncing
        return copy
    }

    static func markCompleted(_ item: SyncWorkItem) -> SyncWorkItem {
        var copy = item
        copy.status = .completed
        return copy
    }

    static func markRetry(_ item: SyncWorkItem) -> SyncWorkItem {
        var copy = item
        copy.retryCount += 1
        copy.status = copy.retryCount >= Self.maxRetries ? .failed : .pending
        return copy
    }

    static func markConflict(_ item: SyncWorkItem) -> SyncWorkItem {
        var copy = item
        copy.status = .requiresResolution
        return copy
    }

    /// The server refused the request itself. Resending the same body cannot succeed.
    static func markFailed(_ item: SyncWorkItem) -> SyncWorkItem {
        var copy = item
        copy.status = .failed
        return copy
    }

    static func isReady(_ item: SyncWorkItem, now: Date, jitterUnit: Double = 0) -> Bool {
        guard item.status == .pending else { return false }
        if item.retryCount == 0 { return true }
        let wait = SyncBackoff.delay(retryCount: item.retryCount - 1, jitterUnit: jitterUnit)
        return now.timeIntervalSince(item.createdAt) >= wait
    }
}

enum SyncSendResult: Equatable, Sendable {
    case applied
    case conflict
    case retry
    case rejected
}

enum SyncDrainer {
    static func drain(
        items: [SyncWorkItem],
        online: Bool,
        now: Date,
        jitterUnit: Double = 0,
        send: (SyncWorkItem) async throws -> SyncSendResult
    ) async -> [SyncWorkItem] {
        guard online else { return items }
        var output: [SyncWorkItem] = []
        for item in items {
            guard SyncQueueMachine.isReady(item, now: now, jitterUnit: jitterUnit) else {
                output.append(item)
                continue
            }
            let syncing = SyncQueueMachine.markSyncing(item)
            do {
                switch try await send(syncing) {
                case .applied:
                    output.append(SyncQueueMachine.markCompleted(syncing))
                case .conflict:
                    output.append(SyncQueueMachine.markConflict(syncing))
                case .retry:
                    output.append(SyncQueueMachine.markRetry(syncing))
                case .rejected:
                    output.append(SyncQueueMachine.markFailed(syncing))
                }
            } catch {
                output.append(SyncQueueMachine.markRetry(syncing))
            }
        }
        return output
    }
}

enum BoardDeltaMerge {
    /// Pending meal edits whose base revision is no longer the server revision.
    static func overriddenMealIDs(pending: [SyncWorkItem], remoteRevisions: [String: Int]) -> [String] {
        pending.compactMap { item in
            guard item.entityType == "meal" || item.entityType == "reaction" else { return nil }
            guard item.status == .pending || item.status == .syncing else { return nil }
            guard let remote = remoteRevisions[item.entityId.lowercased()] else { return nil }
            guard let base = mealRevision(in: item.payload), remote != base else { return nil }
            return item.entityId
        }
    }

    static func mealRevision(in payload: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        let body = object["payload"] as? [String: Any]
        if let revision = body?["mealRevision"] as? Int { return revision }
        if let revision = object["baseRevision"] as? Int, object["entityType"] as? String == "meal" {
            return revision
        }
        return nil
    }
}

@Model
final class PendingOperation {
    var id: UUID
    var entityType: String
    var entityId: String
    var operationType: String
    var payload: Data
    var createdAt: Date
    var retryCount: Int
    var status: String

    init(
        id: UUID,
        entityType: String,
        entityId: String,
        operationType: String,
        payload: Data,
        createdAt: Date,
        retryCount: Int,
        status: String
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.status = status
    }

    var workItem: SyncWorkItem {
        SyncWorkItem(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: payload,
            createdAt: createdAt,
            retryCount: retryCount,
            status: PendingOperationStatus(rawValue: status) ?? .pending
        )
    }
}

enum BoardSyncCursor {
    static func load(householdId: UUID) -> Int {
        UserDefaults.standard.integer(forKey: key(householdId))
    }

    static func save(_ cursor: Int, householdId: UUID) {
        UserDefaults.standard.set(cursor, forKey: key(householdId))
    }

    private static func key(_ householdId: UUID) -> String {
        "mealroutine.boardCursor.\(householdId.uuidString)"
    }
}

enum PendingOperationStore {
    @MainActor
    static func items(in context: ModelContext) -> [SyncWorkItem] {
        let stored = (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? []
        return stored.map(\.workItem).sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    static func replace(_ items: [SyncWorkItem], in context: ModelContext) {
        let stored = (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? []
        for row in stored {
            context.delete(row)
        }
        for item in items {
            context.insert(PendingOperation(
                id: item.id,
                entityType: item.entityType,
                entityId: item.entityId,
                operationType: item.operationType,
                payload: item.payload,
                createdAt: item.createdAt,
                retryCount: item.retryCount,
                status: item.status.rawValue
            ))
        }
        try? context.save()
    }

    /// Replaces every queued operation except those of `entityType`, which keep what is stored now.
    /// Board and personal-recipe drains use this so they never overwrite pantry work queued meanwhile.
    @MainActor
    static func replace(_ items: [SyncWorkItem], keeping entityType: String, in context: ModelContext) {
        let kept = Self.items(in: context).filter { $0.entityType == entityType }
        replace(items.filter { $0.entityType != entityType } + kept, in: context)
    }

    @MainActor
    static func upsert(_ item: SyncWorkItem, in context: ModelContext) {
        var current = items(in: context)
        if let index = current.firstIndex(where: { $0.id == item.id }) {
            current[index] = item
        } else {
            current.append(item)
        }
        replace(current, in: context)
    }
}

/// Watches the network and asks the session to drain when a connection returns.
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private(set) var online = true
    private var onReconnect: (@MainActor () -> Void)?
    private var started = false
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    func start(onReconnect: @escaping @MainActor () -> Void) {
        self.onReconnect = onReconnect
        guard !started else { return }
        started = true
        #if canImport(Network)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                let wasOnline = SyncEngine.shared.online
                SyncEngine.shared.online = satisfied
                if satisfied && !wasOnline {
                    SyncEngine.shared.onReconnect?()
                }
            }
        }
        let queue = DispatchQueue(label: "mealroutine.reachability")
        monitor.start(queue: queue)
        self.monitor = monitor
        #endif
    }
}
