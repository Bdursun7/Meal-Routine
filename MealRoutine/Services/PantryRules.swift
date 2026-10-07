import CryptoKit
import Foundation
import SwiftData

enum PantryCopy {
    static let usesStock = "Evdeki malzemeleri kullanıyor"
    static let approachingExpiry = "Son kullanma tarihi yaklaşıyor"
    static let conflict = "Bu malzeme başka bir cihazda güncellendi."
    static let offline = "Çevrimdışısın. Son kayıtlar gösteriliyor; değişiklikler bağlantı gelince gönderilecek."
    static let loadFailed = "Pantry yüklenemedi. Yeniden dene."
    static let loading = "Pantry yükleniyor"
    static let empty = "Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım."
    static let saveFailed = "Sunucuya kaydedilemedi. Yerel kopya korunuyor; bağlantı gelince tekrar denenecek."
    static let unitMismatch = "Bu birimler birbirine çevrilemiyor. Otomatik düşülmedi."
    static let unitChoice = "Bu malzeme başka bir birimle kayıtlı. Satırlar birleştirilmedi."
    static let finishedTitle = "Bitti"
    static let finishedMessage = "Bitti, Düzenle ya da − değildir. Seçersen stok sıfırlanır. İptal edersen miktar aynı kalır."
    static let addToMarket = "Markete ekle"
    static let missingMinimum = "Eksik miktarı hesapla"
    static let deleteItem = "Öğeyi sil"
    static let noMinimum = "Minimum miktar yok. Eksik hesaplanamadı."
    static let transferTitle = "Kişisel pantry ayrı duruyor"
    static let transferMessage = "Kişisel pantry otomatik olarak ortak veriye karışmaz. Aktar, kopyala veya ayrı tut."
    static let transferMove = "Aktar"
    static let transferCopy = "Kopyala"
    static let transferKeep = "Ayrı tut"
    static let covered = "Evde var"
    static let computeMissing = "Eksik miktarı hesapla"
    static let showFullNeed = "Tam ihtiyacı göster"
    static let consume = "Pantry'den düş"
    static let restock = "Pantry'ye ekle"
    static let useServer = "Sunucudaki hali kullan"
    static let separateUnit = "Ayrı satır olarak ekle"
    static let missingPantry = "Pantry'de bu malzeme yok."
    static let incompatibleCount = "Bazı birimler uyuşmuyor. Onlar otomatik düşülmedi."
}

enum PantryFinishedChoice: String, Equatable, Sendable {
    case addToMarket
    case missingAgainstMinimum
    case deleteItem
}

enum PantryFinishedFlow {
    /// Cancel (`nil`) keeps the current stock. Choosing an option is what zeroes it.
    static func quantity(current: Double, choice: PantryFinishedChoice?) -> Double {
        choice == nil ? current : 0
    }
}

enum PantryFinishedMath {
    /// Missing amount against the optional minimum. Nil when the user never set one.
    static func shortage(quantity: Double, minimum: Double?) -> Double? {
        guard let minimum, minimum >= 0 else { return nil }
        return max(0, minimum - max(0, quantity))
    }
}

enum PantryTransferChoice: String, Equatable, Sendable {
    case move
    case copy
    case keepSeparate
}

enum PantryTransferPolicy {
    static let resolvedKey = "mealroutine.pantryTransfer.resolved"

    static func shouldOffer(personalCount: Int, householdId: UUID?, resolvedHouseholdId: String?) -> Bool {
        guard personalCount > 0, let householdId else { return false }
        return resolvedHouseholdId != householdId.uuidString
    }
}

enum PantryUnitDecision: Equatable, Sendable {
    case merge(quantity: Double, unit: String)
    case separate
    case choiceRequired(existingUnit: String)
    case invalid
}

enum PantryUnitPolicy {
    static let knownCodes: Set<String> = ["g", "kg", "ml", "l", "piece", "tbsp", "tsp", "clove", "pinch", "slice", "sprig", "toTaste"]

    static func isKnown(_ unit: String) -> Bool {
        let parsed = UnitNormalization.parse(unit)
        return knownCodes.contains(parsed.code) && !parsed.code.isEmpty
    }

    static func compatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = UnitNormalization.parse(lhs)
        let right = UnitNormalization.parse(rhs)
        if left.code.isEmpty || right.code.isEmpty { return false }
        if let family = left.family, family == right.family { return true }
        return left.code == right.code
    }

    static func converted(_ value: Double, from: String, to: String) -> Double? {
        guard compatible(from, to) else { return nil }
        let source = UnitNormalization.parse(from)
        let target = UnitNormalization.parse(to)
        if let family = source.family, family == target.family, target.basePerUnit != 0 {
            return snap(value * source.basePerUnit / target.basePerUnit)
        }
        return snap(value)
    }

    static func decision(
        existingUnit: String?,
        existingQuantity: Double,
        incomingUnit: String,
        incomingQuantity: Double,
        confirmSeparate: Bool
    ) -> PantryUnitDecision {
        let incoming = UnitNormalization.parse(incomingUnit)
        if incoming.code.isEmpty { return .invalid }
        if !isKnown(incomingUnit) && !confirmSeparate { return .invalid }
        guard let existingUnit else { return .separate }
        if compatible(existingUnit, incomingUnit) {
            let added = converted(incomingQuantity, from: incomingUnit, to: existingUnit) ?? incomingQuantity
            let code = UnitNormalization.parse(existingUnit).code
            return .merge(quantity: snap(existingQuantity + added), unit: code)
        }
        if confirmSeparate { return .separate }
        return .choiceRequired(existingUnit: UnitNormalization.parse(existingUnit).code)
    }

    static func consume(stockQuantity: Double, stockUnit: String, amount: Double, amountUnit: String) -> Double? {
        guard let taken = converted(amount, from: amountUnit, to: stockUnit) else { return nil }
        return snap(max(0, stockQuantity - taken))
    }

    static func restock(stockQuantity: Double, stockUnit: String, amount: Double, amountUnit: String) -> Double? {
        guard let added = converted(amount, from: amountUnit, to: stockUnit) else { return nil }
        return snap(stockQuantity + added)
    }

    private static func snap(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}

struct PantryMarketLine: Equatable, Sendable {
    var ingredientId: String
    var quantity: Double?
    var unit: String
    var isChecked: Bool
    var preserve: Bool
}

struct PantryMarketAdjustment: Equatable, Sendable {
    var quantity: Double?
    var unit: String
    var incompatible: Bool
    var coveredByPantry: Bool
    var applied: Bool
}

/// Subtracts pantry stock from recipe needs. Checked and preserved rows stay as written.
/// Fully covered needs become zero instead of disappearing. A second call on the same
/// recipe needs returns the same remainder; it does not subtract again.
enum PantryMarketCoverage {
    static func adjust(_ lines: [PantryMarketLine], pantry: [PantryCoverageLine]) -> [PantryMarketAdjustment] {
        var stock = pantry
        return lines.map { line in
            if line.preserve || line.isChecked {
                return PantryMarketAdjustment(
                    quantity: line.quantity,
                    unit: line.unit,
                    incompatible: false,
                    coveredByPantry: false,
                    applied: false
                )
            }
            guard let required = line.quantity else {
                return PantryMarketAdjustment(quantity: nil, unit: line.unit, incompatible: false, coveredByPantry: false, applied: false)
            }
            guard let index = stock.firstIndex(where: { $0.ingredientId == line.ingredientId && PantryUnitPolicy.compatible($0.unit, line.unit) }) else {
                let incompatible = stock.contains { $0.ingredientId == line.ingredientId }
                return PantryMarketAdjustment(quantity: required, unit: line.unit, incompatible: incompatible, coveredByPantry: false, applied: false)
            }
            guard let available = PantryUnitPolicy.converted(stock[index].quantity, from: stock[index].unit, to: line.unit) else {
                return PantryMarketAdjustment(quantity: required, unit: line.unit, incompatible: true, coveredByPantry: false, applied: false)
            }
            if available + 0.000_1 >= required {
                let used = PantryUnitPolicy.converted(required, from: line.unit, to: stock[index].unit) ?? required
                stock[index].quantity = max(0, (stock[index].quantity - used) * 1_000).rounded() / 1_000
                return PantryMarketAdjustment(quantity: 0, unit: line.unit, incompatible: false, coveredByPantry: true, applied: true)
            }
            let remaining = ((required - available) * 1_000).rounded() / 1_000
            stock[index].quantity = 0
            return PantryMarketAdjustment(quantity: remaining, unit: line.unit, incompatible: false, coveredByPantry: false, applied: true)
        }
    }

    static func idempotencyKey(for needs: [PantryReconcileLine]) -> String {
        let raw = needs.map { "\($0.ingredientId)|\($0.quantity)|\($0.unit)|\($0.checked)" }.joined(separator: ";")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct PantryReconcileLine: Equatable, Codable, Sendable {
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var checked: Bool
}

struct PantryCoverageStamp: Equatable, Sendable {
    var applying: Bool
    var needs: [PantryReconcileLine]
    var incompatibleCount: Int

    static let idle = PantryCoverageStamp(applying: false, needs: [], incompatibleCount: 0)
}

enum PantrySyncError: Error, Equatable {
    case conflict
    case unitChoice
    case failed
}

struct PantryQueuedPayload: Codable, Equatable, Sendable {
    var action: String
    var householdID: UUID
    var item: PantryRemoteItem?
    var confirmSeparate: Bool

    private enum CodingKeys: String, CodingKey {
        case action, householdID, item, confirmSeparate
    }

    init(action: String, householdID: UUID, item: PantryRemoteItem?, confirmSeparate: Bool = false) {
        self.action = action
        self.householdID = householdID
        self.item = item
        self.confirmSeparate = confirmSeparate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        householdID = try container.decode(UUID.self, forKey: .householdID)
        item = try container.decodeIfPresent(PantryRemoteItem.self, forKey: .item)
        confirmSeparate = try container.decodeIfPresent(Bool.self, forKey: .confirmSeparate) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(householdID, forKey: .householdID)
        try container.encodeIfPresent(item, forKey: .item)
        try container.encode(confirmSeparate, forKey: .confirmSeparate)
    }
}

enum PantrySync {
    static let entityType = "pantry"

    static func isPantry(_ item: SyncWorkItem) -> Bool {
        item.entityType == entityType
    }

    @MainActor
    static func enqueue(
        action: String,
        householdID: UUID,
        item: PantryRemoteItem,
        in context: ModelContext,
        status: PendingOperationStatus = .pending,
        id: UUID = UUID(),
        confirmSeparate: Bool = false
    ) {
        let payload = PantryQueuedPayload(action: action, householdID: householdID, item: item, confirmSeparate: confirmSeparate)
        guard let data = try? encoder().encode(payload) else { return }
        PendingOperationStore.upsert(
            SyncWorkItem(
                id: id,
                entityType: entityType,
                entityId: item.id.uuidString,
                operationType: action,
                payload: data,
                createdAt: .now,
                retryCount: 0,
                status: status
            ),
            in: context
        )
    }

    static func send(_ work: SyncWorkItem) async -> SyncSendResult {
        guard let payload = try? decoder().decode(PantryQueuedPayload.self, from: work.payload),
              let item = payload.item,
              let api = await repository() else { return .retry }
        do {
            switch payload.action {
            case "create":
                _ = try await api.create(householdId: payload.householdID, item: item, idempotencyKey: work.idempotencyKey, confirmSeparate: payload.confirmSeparate)
            case "update":
                _ = try await api.update(householdId: payload.householdID, item: item, idempotencyKey: work.idempotencyKey)
            case "delete":
                try await api.delete(householdId: payload.householdID, item: item, idempotencyKey: work.idempotencyKey)
            default:
                return .applied
            }
            return .applied
        } catch PantrySyncError.conflict {
            return .conflict
        } catch {
            return .retry
        }
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

enum PantryTransferApply {
    /// Moves or copies personal rows onto the household. Personal rows stay put on copy and on keep.
    /// Compatible units merge. Incompatible units stay on their own row.
    @MainActor
    static func apply(_ choice: PantryTransferChoice, householdID: UUID, in context: ModelContext) -> [PantryItem] {
        guard choice != .keepSeparate else { return [] }
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let personal = items.filter { $0.householdID == nil }
        var household = items.filter { $0.householdID == householdID }
        var touched: [PantryItem] = []
        for item in personal {
            if let index = household.firstIndex(where: { PantryUnitPolicy.compatible($0.unit, item.unit) && $0.ingredientID == item.ingredientID }) {
                let match = household[index]
                if case .merge(let quantity, let unit) = PantryUnitPolicy.decision(
                    existingUnit: match.unit,
                    existingQuantity: match.quantity,
                    incomingUnit: item.unit,
                    incomingQuantity: item.quantity,
                    confirmSeparate: false
                ) {
                    match.quantity = quantity
                    match.unit = unit
                    match.updatedAt = .now
                    match.revision += 1
                    touched.append(match)
                }
            } else {
                let copy = PantryItem(
                    householdID: householdID,
                    ingredientID: item.ingredientID,
                    displayName: item.displayName,
                    quantity: item.quantity,
                    unit: item.unit,
                    location: item.location,
                    minimumQuantity: item.minimumQuantity,
                    bestBefore: item.bestBefore
                )
                context.insert(copy)
                household.append(copy)
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
        for item in items { context.delete(item) }
        let kept = PendingOperationStore.items(in: context).filter { !PantrySync.isPantry($0) }
        PendingOperationStore.replace(kept, in: context)
        try? context.save()
    }
}

extension PantryPlanningSignal {
    static let expiryWindowDays = 3

    static func explanation(candidate: PickerCandidate, stock: [PantryPlanningStock], now: Date = .now) -> String? {
        guard !stock.isEmpty else { return nil }
        let matches = stock.filter { $0.quantity > 0 && candidate.ingredientIds.contains($0.ingredientId) }
        guard !matches.isEmpty else { return nil }
        if matches.contains(where: { approaching($0.bestBefore, now: now) }) {
            return PantryCopy.approachingExpiry
        }
        return PantryCopy.usesStock
    }

    static func annotated(_ explanation: String, candidates: [PickerCandidate], stock: [PantryPlanningStock], now: Date = .now) -> String {
        guard !stock.isEmpty else { return explanation }
        let notes = candidates.compactMap { self.explanation(candidate: $0, stock: stock, now: now) }
        guard let note = notes.first(where: { $0 == PantryCopy.approachingExpiry }) ?? notes.first else { return explanation }
        if explanation.isEmpty { return note }
        return "\(explanation) \(note)"
    }

    private static func approaching(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        guard let distance = calendar.dateComponents([.day], from: start, to: day).day else { return false }
        return distance >= 0 && distance <= expiryWindowDays
    }
}
