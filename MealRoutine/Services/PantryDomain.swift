import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum PantryCopy {
    static let screenTitle = "Evdekiler"
    static let usesStock = "Evdeki malzemeleri kullanıyor"
    static let approachingExpiry = "Tarihi yaklaşan malzemeyi kullanıyor"
    static let conflict = "Bu malzeme başka bir cihazda güncellendi."
    static let offline = "Çevrimdışısın. Son kayıtlar gösteriliyor; değişiklikler bağlantı gelince gönderilecek."
    static let loadFailedTitle = "Evdekiler yüklenemedi"
    static let loadFailed = "Evdekiler yüklenemedi. Yeniden dene."
    static let refreshFailed = "Evdekiler yenilenemedi. Son kayıtlar gösteriliyor."
    static let retry = "Yeniden dene"
    static let loading = "Evdekiler yükleniyor"
    static let emptyTitle = "Evdekiler boş"
    static let empty = "Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım."
    static let addIngredient = "Malzeme ekle"
    static let addAccessibility = "Evdekilere malzeme ekle"
    static let saveFailedTitle = "Evdekiler güncellenemedi"
    static let saveFailed = "Sunucuya kaydedilemedi. Yerel kopya korunuyor; bağlantı gelince tekrar denenecek."
    static let rejected = "Sunucu bu değişikliği kabul etmedi. Değişiklik gönderilmedi."
    static let unitMismatch = "Bu birimler birbirine çevrilemiyor. Otomatik düşülmedi."
    static let unitChoice = "Bu malzeme başka bir birimle kayıtlı. Satırlar birleştirilmedi."
    static let unknownUnit = "Bu birim tanınmıyor. Listeden bilinen bir birim seç."
    static let duplicateRow = "Bu malzeme bu birimle zaten kayıtlı. O satırı düzenle."
    static let finishedTitle = "Bitti"
    static let finishedMessage = "Bitti, Düzenle ya da − değildir. Seçersen stok sıfırlanır. İptal edersen miktar aynı kalır."
    static let addToMarket = "Markete ekle"
    static let missingMinimum = "Eksik miktarı hesapla"
    static let deleteItem = "Öğeyi sil"
    static let noMinimum = "Minimum miktar yok. Eksik hesaplanamadı."
    static let personalBanner = "Kişisel evdekiler yalnız bu telefonda durur. Ev halkı kurarsan aktarıp aktarmayacağını sen seçersin."
    static let transferTitle = "Kişisel evdekiler ayrı duruyor"
    static let transferMessage = "Kişisel evdekiler otomatik olarak ortak veriye karışmaz. Aktar, kopyala veya ayrı tut."
    static let transferMove = "Aktar"
    static let transferCopy = "Kopyala"
    static let transferKeep = "Ayrı tut"
    static let covered = "Evde var"
    static let computeMissing = "Eksik miktarı hesapla"
    static let showFullNeed = "Tam ihtiyacı göster"
    static let consume = "Evdekilerden düş"
    static let restock = "Evdekilere ekle"
    static let useServer = "Sunucudaki hali kullan"
    static let reapplyMine = "Değişikliğimi yeniden uygula"
    static let separateUnit = "Ayrı satır olarak ekle"
    static let missingPantry = "Evdekilerde bu malzeme yok."
    static let incompatibleCount = "Bazı birimler uyuşmuyor. Onlar otomatik düşülmedi."
    static let pending = "Eşitlenmeyi bekliyor"
    static let failed = "Gönderilemedi"
    static let failedMessage = "Evdekilerdeki bazı değişiklikler gönderilemedi. Yeniden dene ya da vazgeç."
    static let discardFailed = "Değişikliklerden vazgeç"
    static let conflictBadge = "Başka cihazda güncellendi"
    static let unmatched = "Sözlükte eşleşmedi"
    static let lowStock = "Azaldı"
    static let outOfStock = "Tükendi"
    static let whichIngredient = "Hangi malzeme?"
    static let ingredientFooter = "Yazdıkça sözlük ve evin malzemeleri önerilir. Öneriye basmazsan ad tek bir malzemeyle birebir örtüşürse ona bağlanır; yoksa yeni malzeme olarak kaydedilir. Benzer adlar birleşmez."
    static let dateSection = "Tarih"
    static let dateFooter = "Son tüketim tarihi (STT) güvenlik içindir. Tavsiye edilen tüketim tarihi (TETT) tat ve tazelik içindir. Tarih girmezsen uygulama tarih uydurmaz."

    static func separateUnitMessage(existing: String) -> String {
        "Evdekilerde \(existing) var. Birimler birbirine çevrilemiyor; ayrı satır olarak ekleyebilirsin."
    }

    /// Strings a person can read. Technical identifiers stay out of this list.
    static let userFacing: [String] = [
        screenTitle, usesStock, approachingExpiry, conflict, offline, loadFailedTitle, loadFailed, refreshFailed,
        retry, loading, emptyTitle, empty, addIngredient, addAccessibility, saveFailedTitle, saveFailed, rejected,
        unitMismatch, unitChoice, unknownUnit, duplicateRow, finishedTitle, finishedMessage, addToMarket,
        missingMinimum, deleteItem, noMinimum, personalBanner, transferTitle, transferMessage, transferMove,
        transferCopy, transferKeep, covered, computeMissing, showFullNeed, consume, restock, useServer, reapplyMine,
        separateUnit, missingPantry, incompatibleCount, pending, failed, failedMessage, discardFailed, conflictBadge,
        unmatched, lowStock, outOfStock, whichIngredient, ingredientFooter, dateSection, dateFooter,
    ]
}

enum PantryLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case pantry, refrigerator, freezer, other
    var id: String { rawValue }
    var title: String {
        switch self { case .pantry: "Kiler"; case .refrigerator: "Buzdolabı"; case .freezer: "Dondurucu"; case .other: "Diğer" }
    }
}

// MARK: - Dates

/// `useBy` is the last safe day; `bestBefore` is quality. They are never shown as the same thing.
enum PantryDateType: String, Codable, CaseIterable, Identifiable, Sendable {
    case bestBefore
    case useBy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .useBy: "Son tüketim tarihi (STT)"
        case .bestBefore: "Tavsiye edilen tüketim tarihi (TETT)"
        }
    }

    var shortTitle: String {
        switch self {
        case .useBy: "Son tüketim"
        case .bestBefore: "Tavsiye edilen"
        }
    }
}

/// Calendar days as the server stores them (`YYYY-MM-DD`), read in the phone's own time zone.
enum PantryDay {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from text: String, calendar: Calendar = .current) -> Date? {
        let pieces = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = pieces[0]; parts.month = pieces[1]; parts.day = pieces[2]
        guard let date = calendar.date(from: parts), string(from: date, calendar: calendar) == String(text.prefix(10)) else { return nil }
        return date
    }
}

enum PantryDateStatus: Equatable, Sendable {
    case none
    case upcoming(daysLeft: Int)
    case approaching(daysLeft: Int)
    /// Safety warning. The app never decides for the user whether the food is still safe.
    case pastUseBy(daysAgo: Int)
    /// Quality and freshness warning only.
    case pastBestBefore(daysAgo: Int)

    static let approachingWindowDays = 3

    static func evaluate(type: PantryDateType?, date: Date?, now: Date, calendar: Calendar = .current) -> PantryDateStatus {
        guard let date else { return .none }
        let start = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let distance = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        if distance < 0 {
            return (type ?? .bestBefore) == .useBy ? .pastUseBy(daysAgo: -distance) : .pastBestBefore(daysAgo: -distance)
        }
        return distance <= approachingWindowDays ? .approaching(daysLeft: distance) : .upcoming(daysLeft: distance)
    }

    var isPastUseBy: Bool { if case .pastUseBy = self { return true }; return false }
    var isApproaching: Bool { if case .approaching = self { return true }; return false }
}

// MARK: - Row presentation

enum PantryBadgeTone: String, Equatable, Sendable {
    case info
    case warning
    case critical
}

struct PantryBadge: Equatable, Hashable, Sendable {
    var text: String
    var symbol: String
    var tone: PantryBadgeTone
}

enum PantrySyncMark: Equatable, Sendable {
    case synced
    case pending
    case conflict
    case failed
}

/// Everything one pantry row shows and speaks. Pure, so the copy and the warnings are testable.
struct PantryRowPresentation: Equatable, Sendable {
    var title: String
    var amount: String
    var location: String
    var minimum: String?
    var date: String?
    var badges: [PantryBadge]
    var accessibilityLabel: String

    static func make(
        name: String,
        ingredientResolved: Bool,
        quantity: Double,
        unit: String,
        location: PantryLocation,
        minimumQuantity: Double?,
        dateType: PantryDateType?,
        dateValue: Date?,
        sync: PantrySyncMark = .synced,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PantryRowPresentation {
        let amount = QuantityFormat.quantityAndUnit(quantity: quantity, unit: unit)
        let minimum = minimumQuantity.map { "Minimum \(QuantityFormat.quantityAndUnit(quantity: $0, unit: unit))" }
        let status = PantryDateStatus.evaluate(type: dateType, date: dateValue, now: now, calendar: calendar)
        let type = dateType ?? .bestBefore
        let dateText = dateValue.map { "\(type.title): \(dayText($0, calendar: calendar))\(relativeSuffix(status))" }

        var badges: [PantryBadge] = []
        switch status {
        case .pastUseBy:
            badges.append(PantryBadge(text: "Güvenlik uyarısı: son tüketim tarihi geçti", symbol: "exclamationmark.octagon.fill", tone: .critical))
        case .pastBestBefore:
            badges.append(PantryBadge(text: "Tazelik uyarısı: tavsiye edilen tarih geçti", symbol: "leaf", tone: .warning))
        case .approaching:
            badges.append(type == .useBy
                ? PantryBadge(text: "Son tüketim tarihi yaklaşıyor", symbol: "clock.badge.exclamationmark", tone: .warning)
                : PantryBadge(text: "Tavsiye edilen tarih yaklaşıyor", symbol: "clock", tone: .info))
        case .none, .upcoming:
            break
        }
        if quantity <= 0 {
            badges.append(PantryBadge(text: PantryCopy.outOfStock, symbol: "tray", tone: .warning))
        } else if let minimumQuantity, quantity <= minimumQuantity {
            badges.append(PantryBadge(text: PantryCopy.lowStock, symbol: "arrow.down.circle", tone: .warning))
        }
        if !ingredientResolved {
            badges.append(PantryBadge(text: PantryCopy.unmatched, symbol: "questionmark.circle", tone: .info))
        }
        switch sync {
        case .synced: break
        case .pending: badges.append(PantryBadge(text: PantryCopy.pending, symbol: "arrow.triangle.2.circlepath", tone: .info))
        case .conflict: badges.append(PantryBadge(text: PantryCopy.conflictBadge, symbol: "exclamationmark.arrow.triangle.2.circlepath", tone: .warning))
        case .failed: badges.append(PantryBadge(text: PantryCopy.failed, symbol: "xmark.icloud", tone: .critical))
        }

        let spoken = [name, amount, location.title, minimum, dateText].compactMap { $0 } + badges.map(\.text)
        return PantryRowPresentation(
            title: name,
            amount: amount,
            location: location.title,
            minimum: minimum,
            date: dateText,
            badges: badges,
            accessibilityLabel: spoken.joined(separator: ", ")
        )
    }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func relativeSuffix(_ status: PantryDateStatus) -> String {
        switch status {
        case .approaching(let days):
            switch days {
            case 0: return " (bugün)"
            case 1: return " (yarın)"
            default: return " (\(days) gün kaldı)"
            }
        case .pastUseBy(let days), .pastBestBefore(let days):
            return days == 1 ? " (dün)" : " (\(days) gün önce)"
        case .none, .upcoming:
            return ""
        }
    }
}

// MARK: - Bitti

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

// MARK: - Personal → household

enum PantryTransferChoice: String, Equatable, Sendable {
    case move
    case copy
    case keepSeparate
}

enum PantryTransferPolicy {
    static let resolvedKey = "mealroutine.pantryTransfer.resolved"

    /// Test mode never offers: its household is fake and a reset wipes it, so moved rows would vanish.
    static func shouldOffer(personalCount: Int, householdId: UUID?, resolvedHouseholdId: String?, testMode: Bool = false) -> Bool {
        guard !testMode, personalCount > 0, let householdId else { return false }
        return resolvedHouseholdId != householdId.uuidString
    }
}

// MARK: - Units

enum PantryUnitDecision: Equatable, Sendable {
    case merge(quantity: Double, unit: String)
    case separate
    case choiceRequired(existingUnit: String)
    case invalid
}

enum PantryUnitPolicy {
    static let knownCodes: Set<String> = ["g", "kg", "ml", "l", "piece", "tbsp", "tsp", "clove", "pinch", "slice", "sprig", "toTaste"]
    /// Order of the unit picker. Every entry is a known code; there is no free-text unit.
    static let pickerUnits = ["piece", "g", "kg", "ml", "l", "tbsp", "tsp", "clove", "slice", "sprig", "pinch", "toTaste"]

    static func isKnown(_ unit: String) -> Bool {
        knownCodes.contains(UnitNormalization.parse(unit).code)
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

    /// Unknown units are rejected outright. `confirmSeparate` only means "keep a known but
    /// incompatible unit on its own row"; it never lets an unknown unit through.
    static func decision(
        existingUnit: String?,
        existingQuantity: Double,
        incomingUnit: String,
        incomingQuantity: Double,
        confirmSeparate: Bool
    ) -> PantryUnitDecision {
        guard isKnown(incomingUnit) else { return .invalid }
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

    /// Quantity to store after an edit. Switching g → kg without retyping keeps the same stock.
    static func editedQuantity(previousQuantity: Double, previousUnit: String, typedQuantity: Double, newUnit: String) -> Double {
        let canonical = UnitNormalization.parse(newUnit).code
        if compatible(previousUnit, canonical), UnitNormalization.parse(previousUnit).code != canonical,
           abs(typedQuantity - previousQuantity) < 0.001,
           let converted = converted(previousQuantity, from: previousUnit, to: canonical) {
            return converted
        }
        return typedQuantity
    }

    /// Thousandths, matching `GroceryMerger.roundedQuantity`.
    static func snap(_ value: Double) -> Double {
        (value * 1_000).rounded() / 1_000
    }
}

// MARK: - Market

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
/// Lines meet only on a shared dictionary id; an id the dictionary cannot resolve matches nothing.
enum PantryMarketCoverage {
    static func adjust(
        _ lines: [PantryMarketLine],
        pantry: [PantryCoverageLine],
        dictionary: IngredientDictionary = .shared
    ) -> [PantryMarketAdjustment] {
        var stock = pantry
        let stockKeys = pantry.map { dictionary.canonicalId($0.ingredientId) }
        return lines.map { line in
            if line.preserve || line.isChecked {
                return PantryMarketAdjustment(quantity: line.quantity, unit: line.unit, incompatible: false, coveredByPantry: false, applied: false)
            }
            guard let required = line.quantity, let key = dictionary.canonicalId(line.ingredientId) else {
                return PantryMarketAdjustment(quantity: line.quantity, unit: line.unit, incompatible: false, coveredByPantry: false, applied: false)
            }
            let sameIngredient = stock.indices.filter { stockKeys[$0] == key }
            guard let index = sameIngredient.first(where: { PantryUnitPolicy.compatible(stock[$0].unit, line.unit) && stock[$0].quantity > 0 })
                    ?? sameIngredient.first(where: { PantryUnitPolicy.compatible(stock[$0].unit, line.unit) }) else {
                return PantryMarketAdjustment(quantity: required, unit: line.unit, incompatible: !sameIngredient.isEmpty, coveredByPantry: false, applied: false)
            }
            guard let available = PantryUnitPolicy.converted(stock[index].quantity, from: stock[index].unit, to: line.unit) else {
                return PantryMarketAdjustment(quantity: required, unit: line.unit, incompatible: true, coveredByPantry: false, applied: false)
            }
            if available + 0.000_1 >= required {
                let used = PantryUnitPolicy.converted(required, from: line.unit, to: stock[index].unit) ?? required
                stock[index].quantity = PantryUnitPolicy.snap(max(0, stock[index].quantity - used))
                return PantryMarketAdjustment(quantity: 0, unit: line.unit, incompatible: false, coveredByPantry: true, applied: true)
            }
            let remaining = PantryUnitPolicy.snap(required - available)
            stock[index].quantity = 0
            return PantryMarketAdjustment(quantity: remaining, unit: line.unit, incompatible: false, coveredByPantry: false, applied: true)
        }
    }

    static func idempotencyKey(for needs: [PantryReconcileLine]) -> String {
        let raw = needs.map { "\($0.ingredientId)|\($0.quantity)|\($0.unit)|\($0.checked)" }.joined(separator: ";")
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
        #endif
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

// MARK: - Wire format

/// One household pantry row as `GET /v1/households/:id/pantry` returns it.
struct PantryRemoteItem: Codable, Equatable, Sendable {
    var id: UUID
    var householdId: UUID
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var location: PantryLocation
    var minimumQuantity: Double?
    var dateType: PantryDateType?
    var dateValue: String?
    var version: Int
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: UUID,
        householdId: UUID,
        ingredientId: String,
        displayName: String,
        quantity: Double,
        unit: String,
        location: PantryLocation,
        minimumQuantity: Double?,
        dateType: PantryDateType?,
        dateValue: String?,
        version: Int,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.householdId = householdId
        self.ingredientId = ingredientId
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.minimumQuantity = minimumQuantity
        self.dateType = dateType
        self.dateValue = dateValue
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, householdId, ingredientId, displayName, quantity, unit, location, minimumQuantity
        case dateType, dateValue, version, createdAt, updatedAt
        case bestBefore, revision
    }

    /// Also reads payloads queued by the pre-gate build (`bestBefore`, `revision`) so nothing queued is lost.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        ingredientId = try container.decode(String.self, forKey: .ingredientId)
        displayName = try container.decode(String.self, forKey: .displayName)
        quantity = try container.decode(Double.self, forKey: .quantity)
        unit = try container.decode(String.self, forKey: .unit)
        location = (try? container.decode(PantryLocation.self, forKey: .location)) ?? .other
        minimumQuantity = try container.decodeIfPresent(Double.self, forKey: .minimumQuantity)
        if let value = try container.decodeIfPresent(String.self, forKey: .dateValue) {
            dateValue = value
            dateType = try container.decodeIfPresent(PantryDateType.self, forKey: .dateType) ?? .bestBefore
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .bestBefore) {
            dateValue = legacy
            dateType = .bestBefore
        } else {
            dateValue = nil
            dateType = nil
        }
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? container.decodeIfPresent(Int.self, forKey: .revision)
            ?? 1
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(ingredientId, forKey: .ingredientId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(minimumQuantity, forKey: .minimumQuantity)
        try container.encodeIfPresent(dateType, forKey: .dateType)
        try container.encodeIfPresent(dateValue, forKey: .dateValue)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

/// Body for `POST .../pantry/items` and `PATCH .../pantry/items/:id`. The server schema is strict:
/// `householdId`, `version` and timestamps are never sent, and cleared fields are sent as `null`.
struct PantryItemBody: Encodable, Equatable, Sendable {
    var id: UUID?
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var location: PantryLocation
    var minimumQuantity: Double?
    var dateType: PantryDateType?
    var dateValue: String?
    var confirmSeparate: Bool?

    static func create(_ item: PantryRemoteItem, confirmSeparate: Bool) -> PantryItemBody {
        PantryItemBody(
            id: item.id,
            ingredientId: item.ingredientId,
            displayName: item.displayName,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            dateType: item.dateValue == nil ? nil : item.dateType,
            dateValue: item.dateType == nil ? nil : item.dateValue,
            confirmSeparate: confirmSeparate ? true : nil
        )
    }

    static func patch(_ item: PantryRemoteItem) -> PantryItemBody {
        var body = create(item, confirmSeparate: false)
        body.id = nil
        return body
    }

    private enum CodingKeys: String, CodingKey {
        case id, ingredientId, displayName, quantity, unit, location, minimumQuantity, dateType, dateValue, confirmSeparate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id?.uuidString.lowercased(), forKey: .id)
        try container.encode(ingredientId, forKey: .ingredientId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        try container.encode(location, forKey: .location)
        try container.encode(minimumQuantity, forKey: .minimumQuantity)
        try container.encode(dateType, forKey: .dateType)
        try container.encode(dateValue, forKey: .dateValue)
        try container.encodeIfPresent(confirmSeparate, forKey: .confirmSeparate)
    }
}

/// Server error body on pantry routes: `{ error, recovery, current? }`.
struct PantryErrorBody: Decodable, Sendable {
    var error: String
    var recovery: String?
    var current: PantryRemoteItem?
}

enum PantrySyncError: Error, Equatable {
    /// Stale `baseVersion`. Carries the server row so the user can see what won.
    case conflict(current: PantryRemoteItem?)
    case unitChoice
    case notFound
    /// Validation or permission failure. Retrying the same request cannot succeed.
    case rejected(code: String)
    case failed

    /// Maps a pantry error response. Nil means "transient, retry later".
    static func classify(status: Int, body: PantryErrorBody?) -> PantrySyncError? {
        let code = body?.error ?? ""
        switch (status, code) {
        case (409, "conflict"): return .conflict(current: body?.current)
        case (409, "pantry_unit_choice"): return .unitChoice
        case (404, _): return .notFound
        case (429, _), (401, _), (500..., _): return nil
        default:
            switch body?.recovery {
            case "fix-input", "refresh-household", "new-key", "choose-unit": return .rejected(code: code.isEmpty ? "http_\(status)" : code)
            case "retry-later", "reauthenticate": return nil
            default: return (400..<500).contains(status) ? .rejected(code: code.isEmpty ? "http_\(status)" : code) : nil
            }
        }
    }
}

/// One queued pantry mutation. The work item's id is the Idempotency-Key and never changes.
struct PantryQueuedPayload: Codable, Equatable, Sendable {
    var action: String
    var householdID: UUID
    /// Values the user saved, as of the moment of the edit.
    var item: PantryRemoteItem?
    /// Server version this edit was made on. Nil for creates.
    var baseVersion: Int?
    var confirmSeparate: Bool
    /// Set when the send hit a stale version. The server row that won.
    var serverItem: PantryRemoteItem?
    var serverDeleted: Bool
    /// Last rejection code, so the UI can explain a failed row.
    var rejection: String?

    private enum CodingKeys: String, CodingKey {
        case action, householdID, item, baseVersion, confirmSeparate, serverItem, serverDeleted, rejection
    }

    init(
        action: String,
        householdID: UUID,
        item: PantryRemoteItem?,
        baseVersion: Int? = nil,
        confirmSeparate: Bool = false,
        serverItem: PantryRemoteItem? = nil,
        serverDeleted: Bool = false,
        rejection: String? = nil
    ) {
        self.action = action
        self.householdID = householdID
        self.item = item
        self.baseVersion = baseVersion
        self.confirmSeparate = confirmSeparate
        self.serverItem = serverItem
        self.serverDeleted = serverDeleted
        self.rejection = rejection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        householdID = try container.decode(UUID.self, forKey: .householdID)
        item = try container.decodeIfPresent(PantryRemoteItem.self, forKey: .item)
        confirmSeparate = try container.decodeIfPresent(Bool.self, forKey: .confirmSeparate) ?? false
        serverItem = try container.decodeIfPresent(PantryRemoteItem.self, forKey: .serverItem)
        serverDeleted = try container.decodeIfPresent(Bool.self, forKey: .serverDeleted) ?? false
        rejection = try container.decodeIfPresent(String.self, forKey: .rejection)
        // Pre-gate payloads stored the base as `item.revision`.
        baseVersion = try container.decodeIfPresent(Int.self, forKey: .baseVersion)
            ?? (action == "create" ? nil : item?.version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(householdID, forKey: .householdID)
        try container.encodeIfPresent(item, forKey: .item)
        try container.encodeIfPresent(baseVersion, forKey: .baseVersion)
        try container.encode(confirmSeparate, forKey: .confirmSeparate)
        try container.encodeIfPresent(serverItem, forKey: .serverItem)
        try container.encode(serverDeleted, forKey: .serverDeleted)
        try container.encodeIfPresent(rejection, forKey: .rejection)
    }
}

// MARK: - Typed ingredient

/// What saving a typed name means. Identity is still `ingredientId`.
/// A partial or similar name never links: "Domates" and "Cherry domates" stay apart.
enum PantryIngredientResolution: Equatable, Sendable {
    case linked(IngredientEntry)
    case createCustom(name: String)
}

enum PantryIngredientMatching {
    /// Suggestions while the field is non-empty. Blank text does not dump the dictionary.
    static func suggestions(
        matching query: String,
        dictionary: IngredientDictionary = .shared,
        customs: [IngredientEntry] = [],
        limit: Int = 8
    ) -> [IngredientEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return dictionary.search(trimmed, including: customs, limit: limit)
    }

    /// A pinned row wins while the text still belongs to it. Otherwise one exact
    /// name or synonym (case and diacritics ignored) links that entry. Zero or
    /// several exact hits become a new `custom:<uuid>` — the caller mints the id.
    static func resolve(
        typed raw: String,
        pinnedId: String? = nil,
        pinnedName: String = "",
        dictionary: IngredientDictionary = .shared,
        customs: [IngredientEntry] = []
    ) -> PantryIngredientResolution? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folded = IngredientDictionary.fold(trimmed)
        if let pinnedId {
            let unchanged = !pinnedName.isEmpty && IngredientDictionary.fold(pinnedName) == folded
            if let entry = storedEntry(id: pinnedId, dictionary: dictionary, customs: customs) {
                if unchanged {
                    if matches(entry, folded: folded) { return .linked(entry) }
                    return .linked(IngredientEntry(id: entry.id, name: trimmed, synonyms: entry.synonyms, sourceIds: entry.sourceIds))
                }
                if matches(entry, folded: folded) { return .linked(entry) }
            } else if unchanged {
                return .linked(IngredientEntry(id: pinnedId, name: trimmed))
            }
        }
        let exact = exactEntries(named: trimmed, dictionary: dictionary, customs: customs)
        if exact.count == 1, let only = exact.first { return .linked(only) }
        return .createCustom(name: trimmed)
    }

    static func exactEntries(
        named raw: String,
        dictionary: IngredientDictionary,
        customs: [IngredientEntry]
    ) -> [IngredientEntry] {
        let folded = IngredientDictionary.fold(raw)
        guard !folded.isEmpty else { return [] }
        var found: [IngredientEntry] = []
        var seen = Set<String>()
        for entry in customs + dictionary.entries {
            guard seen.insert(entry.id.lowercased()).inserted else { continue }
            if matches(entry, folded: folded) { found.append(entry) }
        }
        return found
    }

    private static func storedEntry(
        id: String,
        dictionary: IngredientDictionary,
        customs: [IngredientEntry]
    ) -> IngredientEntry? {
        if let entry = dictionary.entry(id) { return entry }
        let lowered = id.lowercased()
        return customs.first { $0.id.lowercased() == lowered }
    }

    private static func matches(_ entry: IngredientEntry, folded: String) -> Bool {
        guard !folded.isEmpty else { return false }
        let names = [entry.name] + entry.synonyms
        return names.contains { IngredientDictionary.fold($0) == folded }
    }
}

// MARK: - Edit form

/// Values shown in the pantry sheet. Built from the item up front so a reused sheet
/// cannot open on an empty amount, and so opening the sheet never writes stock.
struct PantryFormDraft: Equatable {
    var ingredientId: String?
    var name: String
    /// Display name last tied to `ingredientId`: the loaded row, or a tapped suggestion.
    var anchorName: String
    var isNewCustom: Bool
    var quantityText: String
    var unit: String
    /// A stored unit the picker does not know. Shown so the user picks a real one; never saved.
    var legacyUnit: String?
    var location: PantryLocation
    var hasMinimum: Bool
    var minimumText: String
    var hasDate: Bool
    var dateType: PantryDateType
    var date: Date

    static let empty = PantryFormDraft(
        ingredientId: nil,
        name: "",
        anchorName: "",
        isNewCustom: false,
        quantityText: "",
        unit: "piece",
        legacyUnit: nil,
        location: .pantry,
        hasMinimum: false,
        minimumText: "",
        hasDate: false,
        dateType: .bestBefore,
        date: Date(timeIntervalSince1970: 0)
    )

    static func loaded(
        ingredientId: String? = nil,
        name: String,
        quantity: Double,
        unit: String,
        location: PantryLocation,
        minimumQuantity: Double?,
        dateType: PantryDateType? = nil,
        dateValue: Date? = nil,
        dictionary: IngredientDictionary = .shared,
        now: Date = .now
    ) -> PantryFormDraft {
        var draft = empty
        draft.date = now
        draft.ingredientId = ingredientId.flatMap { dictionary.canonicalId($0) }
        draft.name = name
        draft.anchorName = name
        draft.quantityText = QuantityFormat.string(quantity)
        draft.location = location
        let canonical = UnitNormalization.parse(unit).code
        if PantryUnitPolicy.isKnown(unit), PantryUnitPolicy.pickerUnits.contains(canonical) {
            draft.unit = canonical
        } else {
            draft.unit = ""
            draft.legacyUnit = unit
        }
        if let minimumQuantity {
            draft.hasMinimum = true
            draft.minimumText = QuantityFormat.string(minimumQuantity)
        }
        if let dateValue {
            draft.hasDate = true
            draft.dateType = dateType ?? .bestBefore
            draft.date = dateValue
        }
        return draft
    }

    mutating func choose(_ entry: IngredientEntry, isNewCustom: Bool) {
        ingredientId = entry.id
        name = entry.name
        anchorName = entry.name
        self.isNewCustom = isNewCustom
    }

    /// Nil when the name is blank. A tapped or loaded id is kept while the text still
    /// belongs to it; otherwise one exact match links and anything else is custom.
    func resolvedIngredient(
        dictionary: IngredientDictionary,
        customs: [IngredientEntry] = []
    ) -> PantryIngredientResolution? {
        PantryIngredientMatching.resolve(
            typed: name,
            pinnedId: ingredientId,
            pinnedName: anchorName,
            dictionary: dictionary,
            customs: customs
        )
    }

    /// Nil when the field is empty or not a finite, non-negative number. Never substitutes 0.
    var quantityToSave: Double? { Self.parseQuantity(quantityText) }

    var minimumToSave: Double? { hasMinimum ? Self.parseQuantity(minimumText) : nil }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityToSave != nil
            && PantryUnitPolicy.isKnown(unit)
            && (!hasMinimum || minimumToSave != nil)
    }

    static func parseQuantity(_ text: String) -> Double? {
        GroceryQuantityEdit.parse(text)
    }
}

// MARK: - Planner

extension PantryPlanningSignal {
    static let expiryWindowDays = PantryDateStatus.approachingWindowDays

    static func explanation(
        candidate: PickerCandidate,
        stock: [PantryPlanningStock],
        now: Date = .now,
        dictionary: IngredientDictionary = .shared
    ) -> String? {
        guard !stock.isEmpty else { return nil }
        let matches = usable(stock, now: now, dictionary: dictionary).filter { candidateKeys(candidate, dictionary).contains($0.key) }
        guard !matches.isEmpty else { return nil }
        if matches.contains(where: { $0.status.isApproaching }) {
            return PantryCopy.approachingExpiry
        }
        return PantryCopy.usesStock
    }

    static func annotated(
        _ explanation: String,
        candidates: [PickerCandidate],
        stock: [PantryPlanningStock],
        now: Date = .now,
        dictionary: IngredientDictionary = .shared
    ) -> String {
        guard !stock.isEmpty else { return explanation }
        let notes = candidates.compactMap { self.explanation(candidate: $0, stock: stock, now: now, dictionary: dictionary) }
        guard let note = notes.first(where: { $0 == PantryCopy.approachingExpiry }) ?? notes.first else { return explanation }
        if explanation.isEmpty { return note }
        return "\(explanation) \(note)"
    }
}
