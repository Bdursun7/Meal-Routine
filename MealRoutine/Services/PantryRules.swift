import Foundation
import SwiftData

extension PantryItem {
    /// Snapshot of the row as the user saved it. Only household rows ever leave the phone.
    func remote(householdID: UUID) -> PantryRemoteItem {
        PantryRemoteItem(
            id: uuid,
            householdId: householdID,
            ingredientId: ingredientID,
            displayName: displayName,
            quantity: quantity,
            unit: unit,
            location: location,
            minimumQuantity: minimumQuantity,
            dateType: dateType,
            dateValue: dateValue.map { PantryDay.string(from: $0) },
            version: revision,
            updatedAt: updatedAt
        )
    }

    /// Server state wins for every field on the row.
    func apply(_ remote: PantryRemoteItem) {
        ingredientID = remote.ingredientId
        displayName = remote.displayName
        quantity = remote.quantity
        unit = remote.unit
        location = remote.location
        minimumQuantity = remote.minimumQuantity
        setDate(remote.dateType, remote.dateValue.flatMap { PantryDay.date(from: $0) })
        revision = remote.version
        updatedAt = remote.updatedAt ?? .now
    }

    convenience init(remote: PantryRemoteItem) {
        self.init(
            uuid: remote.id,
            householdID: remote.householdId,
            ingredientID: remote.ingredientId,
            displayName: remote.displayName,
            quantity: remote.quantity,
            unit: remote.unit,
            location: remote.location,
            minimumQuantity: remote.minimumQuantity,
            dateType: remote.dateType,
            dateValue: remote.dateValue.flatMap { PantryDay.date(from: $0) },
            revision: remote.version,
            updatedAt: remote.updatedAt ?? .now
        )
    }

    var ingredientResolved: Bool { IngredientDictionary.shared.canonicalId(ingredientID) != nil }
}

enum PantrySync {
    static let entityType = "pantry"

    static func isPantry(_ item: SyncWorkItem) -> Bool {
        item.entityType == entityType
    }

    static func payload(of item: SyncWorkItem) -> PantryQueuedPayload? {
        try? decoder().decode(PantryQueuedPayload.self, from: item.payload)
    }

    static func encode(_ payload: PantryQueuedPayload) -> Data? {
        try? encoder().encode(payload)
    }

    @MainActor
    static func repository() -> PantryRepository? {
        guard let baseURL = MealRoutineConfig.apiBaseURL, AuthServices.sharedTokens.load() != nil else { return nil }
        return PantryRepository(client: APIClient(
            baseURL: baseURL,
            tokens: AuthServices.sharedTokens,
            refreshGate: AuthServices.refreshGate,
            expiry: AuthServices.expiry
        ))
    }

    /// Sends one queued mutation. Returns the result plus a payload to store when the
    /// server told us something the user must see (the winning row, or why it was refused).
    @MainActor
    static func send(_ work: SyncWorkItem, in context: ModelContext) async -> (SyncSendResult, Data?) {
        guard var payload = payload(of: work) else { return (.rejected, nil) }
        guard let api = repository() else { return (.retry, nil) }
        do {
            switch payload.action {
            case "create":
                guard let item = payload.item else { return (.rejected, nil) }
                try await registerIfCustom(item, householdID: payload.householdID, api: api, key: work.idempotencyKey)
                let saved = try await api.create(householdId: payload.householdID, item: item, idempotencyKey: work.idempotencyKey, confirmSeparate: payload.confirmSeparate)
                PantryOutbox.confirm(saved, localID: item.id, work: work, in: context)
            case "update":
                guard let item = payload.item else { return (.rejected, nil) }
                try await registerIfCustom(item, householdID: payload.householdID, api: api, key: work.idempotencyKey)
                let saved = try await api.update(householdId: payload.householdID, item: item, baseVersion: payload.baseVersion ?? item.version, idempotencyKey: work.idempotencyKey)
                PantryOutbox.confirm(saved, localID: item.id, work: work, in: context)
            case "delete":
                guard let id = UUID(uuidString: work.entityId) else { return (.rejected, nil) }
                do {
                    try await api.delete(householdId: payload.householdID, itemId: id, baseVersion: payload.baseVersion, idempotencyKey: work.idempotencyKey)
                } catch PantrySyncError.notFound {
                    // Already gone on the server: the state the user asked for.
                }
            default:
                return (.rejected, nil)
            }
            return (.applied, nil)
        } catch PantrySyncError.conflict(let current) {
            payload.serverItem = current
            payload.serverDeleted = false
            if let current { PantryOutbox.showServer(current, in: context) }
            return (.conflict, encode(payload))
        } catch PantrySyncError.notFound where payload.action == "update" {
            payload.serverItem = nil
            payload.serverDeleted = true
            return (.conflict, encode(payload))
        } catch PantrySyncError.unitChoice {
            payload.serverItem = nil
            payload.serverDeleted = false
            payload.rejection = "pantry_unit_choice"
            return (.conflict, encode(payload))
        } catch PantrySyncError.rejected(let code) {
            payload.rejection = code
            return (.rejected, encode(payload))
        } catch PantrySyncError.notFound {
            payload.rejection = "not_found"
            return (.rejected, encode(payload))
        } catch {
            return (.retry, nil)
        }
    }

    @MainActor
    private static func registerIfCustom(_ item: PantryRemoteItem, householdID: UUID, api: PantryRepository, key: String) async throws {
        guard IngredientDictionary.isCustom(item.ingredientId) else { return }
        let saved = try await api.registerIngredient(householdId: householdID, id: item.ingredientId.lowercased(), displayName: item.displayName, idempotencyKey: "\(key)-ingredient")
        PantryIngredientStore.remember(saved.entry, householdID: householdID)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Every household pantry write goes through here: the local cache changes first, the
/// mutation is queued with a fixed Idempotency-Key, then sent. Nothing is dropped on failure.
@MainActor
enum PantryOutbox {
    private static var flushing = false
    private static var rerun = false

    /// Test mode and builds without an API keep household rows on the phone only.
    static var syncsHousehold: Bool {
        !HouseholdSession.shared.isTestMode && MealRoutineConfig.apiBaseURL != nil
    }

    enum Action: String {
        case create, update, delete
    }

    /// Queues the edit for a household row. `baseVersion` is the server version the edit was made on.
    @discardableResult
    static func record(
        _ action: Action,
        _ item: PantryItem,
        baseVersion: Int?,
        confirmSeparate: Bool = false,
        in context: ModelContext
    ) -> Bool {
        guard syncsHousehold, let householdID = item.householdID else { return false }
        let payload = PantryQueuedPayload(
            action: action.rawValue,
            householdID: householdID,
            item: item.remote(householdID: householdID),
            baseVersion: action == .create ? nil : baseVersion,
            confirmSeparate: confirmSeparate
        )
        guard let data = PantrySync.encode(payload) else { return false }
        PendingOperationStore.upsert(
            SyncWorkItem(
                id: UUID(),
                entityType: PantrySync.entityType,
                entityId: item.uuid.uuidString.lowercased(),
                operationType: action.rawValue,
                payload: data,
                createdAt: .now,
                retryCount: 0,
                status: .pending
            ),
            in: context
        )
        return true
    }

    /// Sends queued pantry work in order. Returns true when a new conflict needs the user.
    @discardableResult
    static func flush(in context: ModelContext) async -> Bool {
        guard !flushing else {
            rerun = true
            return false
        }
        flushing = true
        defer { flushing = false }
        var conflicted = false
        repeat {
            rerun = false
            let queued = PendingOperationStore.items(in: context).filter(PantrySync.isPantry)
            guard !queued.isEmpty else { break }
            var blocked = Set(queued.filter { $0.status == .requiresResolution }.map(\.entityId))
            var notes: [UUID: Data] = [:]
            let drained = await SyncDrainer.drain(items: queued, online: SyncEngine.shared.online, now: .now) { work in
                // Later edits on a row that is waiting for the user would only hit the same stale version.
                if blocked.contains(work.entityId) { return .conflict }
                let (result, note) = await PantrySync.send(work, in: context)
                if let note { notes[work.id] = note }
                if result == .conflict { blocked.insert(work.entityId) }
                return result
            }
            conflicted = conflicted || drained.contains { item in
                item.status == .requiresResolution && queued.first { $0.id == item.id }?.status != .requiresResolution
            }
            let kept = drained.filter { $0.status != .completed }.map { item -> SyncWorkItem in
                var copy = item
                if let note = notes[item.id] { copy.payload = note }
                return copy
            }
            let current = PendingOperationStore.items(in: context)
            let drainedIDs = Set(queued.map(\.id))
            PendingOperationStore.replace(current.filter { !drainedIDs.contains($0.id) } + kept, in: context)
        } while rerun
        return conflicted
    }

    static func operations(in context: ModelContext) -> [SyncWorkItem] {
        PendingOperationStore.items(in: context).filter(PantrySync.isPantry)
    }

    static func marks(_ operations: [SyncWorkItem]) -> [String: PantrySyncMark] {
        var marks: [String: PantrySyncMark] = [:]
        for operation in operations where operation.status != .completed {
            let mark: PantrySyncMark = switch operation.status {
            case .requiresResolution: .conflict
            case .failed: .failed
            default: .pending
            }
            let rank: (PantrySyncMark) -> Int = { $0 == .conflict ? 3 : $0 == .failed ? 2 : $0 == .pending ? 1 : 0 }
            if rank(mark) > rank(marks[operation.entityId] ?? .synced) { marks[operation.entityId] = mark }
        }
        return marks
    }

    /// Writes the server's answer to the cache. Later local edits on the same row stay visible.
    static func confirm(_ saved: PantryRemoteItem, localID: UUID, work: SyncWorkItem, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let later = operations(in: context).contains { other in
            other.id != work.id && other.entityId == work.entityId && other.createdAt >= work.createdAt && other.status != .completed
        }
        if saved.id != localID {
            // The server merged a compatible row into one it already had.
            if !later, let local = rows.first(where: { $0.uuid == localID }) { context.delete(local) }
            if let existing = rows.first(where: { $0.uuid == saved.id }) { existing.apply(saved) } else { context.insert(PantryItem(remote: saved)) }
        } else if let local = rows.first(where: { $0.uuid == saved.id }) {
            if later { local.revision = max(local.revision, saved.version) } else { local.apply(saved) }
        } else if !later {
            context.insert(PantryItem(remote: saved))
        }
        try? context.save()
    }

    /// Conflict: the cache shows what the server has. The user's edit stays queued for "reapply".
    static func showServer(_ current: PantryRemoteItem, in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        if let local = rows.first(where: { $0.uuid == current.id }) { local.apply(current) } else { context.insert(PantryItem(remote: current)) }
        try? context.save()
    }

    /// "Sunucudaki hali kullan": drop this row's queued edits and show the server row.
    static func useServer(entityId: String, in context: ModelContext) {
        let all = PendingOperationStore.items(in: context)
        let mine = all.filter { PantrySync.isPantry($0) && $0.entityId == entityId }
        let conflict = mine.compactMap(PantrySync.payload(of:)).first { $0.serverItem != nil || $0.serverDeleted || $0.rejection == "pantry_unit_choice" }
        PendingOperationStore.replace(all.filter { !(PantrySync.isPantry($0) && $0.entityId == entityId) }, in: context)
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        if let server = conflict?.serverItem {
            showServer(server, in: context)
        } else if let local = rows.first(where: { $0.uuid.uuidString.lowercased() == entityId }), conflict?.serverDeleted == true || conflict?.rejection == "pantry_unit_choice" {
            context.delete(local)
            try? context.save()
        }
    }

    /// "Değişikliğimi yeniden uygula": the user's last values, sent on top of the server version.
    static func reapply(entityId: String, in context: ModelContext) {
        let all = PendingOperationStore.items(in: context)
        let mine = all.filter { PantrySync.isPantry($0) && $0.entityId == entityId }
        let payloads = mine.compactMap(PantrySync.payload(of:))
        guard let lastEdit = payloads.last, let conflict = payloads.first(where: { $0.serverItem != nil || $0.serverDeleted || $0.rejection == "pantry_unit_choice" }) else { return }
        PendingOperationStore.replace(all.filter { !(PantrySync.isPantry($0) && $0.entityId == entityId) }, in: context)
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        if lastEdit.action == "delete" {
            guard let server = conflict.serverItem else { return }
            let row = rows.first { $0.uuid == server.id }
            if let row { context.delete(row) }
            try? context.save()
            let ghost = PantryItem(remote: server)
            enqueueRaw(.delete, ghost, householdID: lastEdit.householdID, baseVersion: server.version, confirmSeparate: false, in: context)
            return
        }
        guard let mineItem = lastEdit.item else { return }
        let local = rows.first { $0.uuid == mineItem.id } ?? {
            let inserted = PantryItem(remote: mineItem)
            context.insert(inserted)
            return inserted
        }()
        local.apply(mineItem)
        if conflict.serverDeleted || conflict.rejection == "pantry_unit_choice" {
            local.revision = 1
            try? context.save()
            record(.create, local, baseVersion: nil, confirmSeparate: true, in: context)
        } else if let server = conflict.serverItem {
            local.revision = server.version + 1
            try? context.save()
            record(.update, local, baseVersion: server.version, in: context)
        }
    }

    static func retryFailed(in context: ModelContext) {
        let items = PendingOperationStore.items(in: context).map { item -> SyncWorkItem in
            guard PantrySync.isPantry(item), item.status == .failed else { return item }
            var copy = item
            copy.status = .pending
            copy.retryCount = 0
            copy.createdAt = .now
            return copy
        }
        PendingOperationStore.replace(items, in: context)
    }

    /// Drops refused edits and reloads those rows from the server on the next refresh.
    static func discardFailed(in context: ModelContext) {
        let all = PendingOperationStore.items(in: context)
        let failed = Set(all.filter { PantrySync.isPantry($0) && $0.status == .failed }.map(\.entityId))
        PendingOperationStore.replace(all.filter { !(PantrySync.isPantry($0) && failed.contains($0.entityId)) }, in: context)
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        for row in rows where row.householdID != nil && failed.contains(row.uuid.uuidString.lowercased()) {
            context.delete(row)
        }
        try? context.save()
    }

    private static func enqueueRaw(_ action: Action, _ item: PantryItem, householdID: UUID, baseVersion: Int?, confirmSeparate: Bool, in context: ModelContext) {
        let payload = PantryQueuedPayload(action: action.rawValue, householdID: householdID, item: item.remote(householdID: householdID), baseVersion: baseVersion, confirmSeparate: confirmSeparate)
        guard let data = PantrySync.encode(payload) else { return }
        PendingOperationStore.upsert(
            SyncWorkItem(id: UUID(), entityType: PantrySync.entityType, entityId: item.uuid.uuidString.lowercased(), operationType: action.rawValue, payload: data, createdAt: .now, retryCount: 0, status: .pending),
            in: context
        )
    }
}

/// Pulls the household pantry. Server rows replace cached ones, except rows with edits still
/// queued; those keep the user's values until the queue answers.
@MainActor
enum PantryCache {
    static func refresh(householdID: UUID, in context: ModelContext) async throws {
        guard let api = PantrySync.repository() else { return }
        let remote = try await api.list(householdId: householdID)
        if let dictionary = try? await api.ingredients(householdId: householdID) {
            PantryIngredientStore.replaceCustoms(dictionary.filter { $0.scope == "household" }.map(\.entry), householdID: householdID)
        }
        apply(remote, householdID: householdID, operations: PantryOutbox.operations(in: context), in: context)
    }

    static func apply(_ remote: [PantryRemoteItem], householdID: UUID, operations: [SyncWorkItem], in context: ModelContext) {
        let rows = ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? []).filter { $0.householdID == householdID }
        let waiting = Set(operations.filter { $0.status == .pending || $0.status == .syncing || $0.status == .failed }.map(\.entityId))
        let remoteIDs = Set(remote.map(\.id))
        for item in remote {
            let key = item.id.uuidString.lowercased()
            if let local = rows.first(where: { $0.uuid == item.id }) {
                if !waiting.contains(key) { local.apply(item) }
            } else if !operations.contains(where: { $0.entityId == key && $0.operationType == "delete" }) {
                context.insert(PantryItem(remote: item))
            }
        }
        for local in rows where !remoteIDs.contains(local.uuid) {
            let key = local.uuid.uuidString.lowercased()
            if !operations.contains(where: { $0.entityId == key }) { context.delete(local) }
        }
        try? context.save()
    }
}

/// Household ingredients created with "Yeni malzeme olarak ekle", as the server last listed them.
@MainActor
enum PantryIngredientStore {
    private static func key(_ householdID: UUID?) -> String {
        "mealroutine.pantry.customIngredients.\(householdID?.uuidString.lowercased() ?? "personal")"
    }

    static func customs(householdID: UUID?, items: [PantryItem]) -> [IngredientEntry] {
        var entries: [String: IngredientEntry] = [:]
        if let data = UserDefaults.standard.data(forKey: key(householdID)),
           let stored = try? JSONDecoder().decode([IngredientEntry].self, from: data) {
            for entry in stored { entries[entry.id] = entry }
        }
        for item in items where item.householdID == householdID && IngredientDictionary.isCustom(item.ingredientID) {
            let id = item.ingredientID.lowercased()
            if entries[id] == nil { entries[id] = IngredientEntry(id: id, name: item.displayName) }
        }
        return entries.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func remember(_ entry: IngredientEntry, householdID: UUID?) {
        var current = stored(householdID)
        current.removeAll { $0.id == entry.id }
        current.append(entry)
        save(current, householdID: householdID)
    }

    static func replaceCustoms(_ entries: [IngredientEntry], householdID: UUID) {
        save(entries, householdID: householdID)
    }

    static func clear(householdID: UUID?) {
        UserDefaults.standard.removeObject(forKey: key(householdID))
    }

    private static func stored(_ householdID: UUID?) -> [IngredientEntry] {
        guard let data = UserDefaults.standard.data(forKey: key(householdID)) else { return [] }
        return (try? JSONDecoder().decode([IngredientEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [IngredientEntry], householdID: UUID?) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key(householdID)) }
    }
}

enum PantryTransferApply {
    /// Moves or copies personal rows onto the household. Personal rows stay put on copy and on keep.
    /// Rows meet only on the same dictionary id; compatible units merge, incompatible ones stay apart.
    /// Every touched household row is queued for the server.
    @MainActor
    @discardableResult
    static func apply(_ choice: PantryTransferChoice, householdID: UUID, in context: ModelContext) -> [PantryItem] {
        guard choice != .keepSeparate else { return [] }
        let dictionary = IngredientDictionary.shared
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let personal = items.filter { $0.householdID == nil }
        var household = items.filter { $0.householdID == householdID }
        var touched: [PantryItem] = []
        for item in personal {
            let key = dictionary.canonicalId(item.ingredientID)
            let index = key.flatMap { key in
                household.firstIndex { dictionary.canonicalId($0.ingredientID) == key && PantryUnitPolicy.compatible($0.unit, item.unit) }
            }
            if let index, case .merge(let quantity, let unit) = PantryUnitPolicy.decision(
                existingUnit: household[index].unit,
                existingQuantity: household[index].quantity,
                incomingUnit: item.unit,
                incomingQuantity: item.quantity,
                confirmSeparate: false
            ) {
                let match = household[index]
                let base = match.revision
                match.quantity = quantity
                match.unit = unit
                match.updatedAt = .now
                match.revision += 1
                PantryOutbox.record(.update, match, baseVersion: base, in: context)
                touched.append(match)
            } else {
                let copy = PantryItem(
                    householdID: householdID,
                    ingredientID: key ?? item.ingredientID,
                    displayName: item.displayName,
                    quantity: item.quantity,
                    unit: item.unit,
                    location: item.location,
                    minimumQuantity: item.minimumQuantity,
                    dateType: item.dateType,
                    dateValue: item.dateValue
                )
                context.insert(copy)
                household.append(copy)
                // Unresolved legacy ids cannot be stored on the server; the row stays local until the user picks the ingredient.
                if key != nil {
                    PantryOutbox.record(.create, copy, baseVersion: nil, confirmSeparate: true, in: context)
                }
                touched.append(copy)
            }
            if choice == .move { context.delete(item) }
        }
        try? context.save()
        return touched
    }
}

enum PantryAccountPrivacy {
    /// The deleted account's phone drops personal pantry and the cached household copy.
    /// The server keeps household pantry when another member remains.
    @MainActor
    static func eraseLocal(in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        for item in items {
            PantryIngredientStore.clear(householdID: item.householdID)
            context.delete(item)
        }
        PantryIngredientStore.clear(householdID: nil)
        let kept = PendingOperationStore.items(in: context).filter { !PantrySync.isPantry($0) }
        PendingOperationStore.replace(kept, in: context)
        try? context.save()
    }

    /// After leaving or deleting a household the phone keeps no hidden copy of its pantry.
    @MainActor
    static func dropHouseholdCache(householdID: UUID, in context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        for item in items where item.householdID == householdID { context.delete(item) }
        PantryIngredientStore.clear(householdID: householdID)
        let kept = PendingOperationStore.items(in: context).filter { item in
            guard PantrySync.isPantry(item) else { return true }
            return PantrySync.payload(of: item)?.householdID != householdID
        }
        PendingOperationStore.replace(kept, in: context)
        try? context.save()
    }
}
