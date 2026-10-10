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
    static let dateFooter = "Pakette yazan tarih türünü seç ve tarihi aynen gir. Tarih girmezsen uygulama tarih uydurmaz."
    static let pastUseBy = "Girilen son tüketim tarihi geçti"
    static let pastBestBefore = "Girilen tavsiye edilen tüketim tarihi geçti"
    static let cookConfirmTitle = "Evdekilerden düşülsün mü?"
    static let cookConfirmMessage = "Tarifin malzemeleri ve evdeki miktarlar aşağıda. Onaylamazsan stok değişmez."
    static let cookConfirm = "Stoktan düş"
    static let cookDecline = "Stoktan düşme"
    static let addMissingToMarket = "Eksik miktarı markete ekle"
    static let autoAddToggle = "Minimumun altına inince markete ekle"
    static let autoAddFooter = "Kapalıyken eşik, market listesine ürün eklemez. Açınca eksik miktar bir kez yazılır."
    static let lowStockToggle = "Düşük stok bildirimi"
    static let dateReminderToggle = "Tarih hatırlatması"
    static let dateReminderScheduleToggle = "Hatırlatma günleri"
    static let dateReminderFooter = "Tavsiye edilen tarih için 2 gün önce ve o gün. Son tüketim tarihi için 1 gün önce ve o gün. Bu bir hatırlatmadır."
    static let notificationPermissionDenied = "Bildirim izni kapalı. Evdekiler çalışmaya devam eder; hatırlatma gönderilmez."
    static let lowStockNoticeTitle = "Evdekiler"

    static func lowStockNoticeBody(name: String) -> String {
        "\(name) minimum miktara ulaştı."
    }

    static func reminderBestBefore(name: String, day: String) -> String {
        "\(name): girdiğin tavsiye edilen tarih \(day)."
    }

    static func reminderUseBy(name: String, day: String) -> String {
        "\(name): girdiğin son tüketim tarihi \(day)."
    }

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
        pastUseBy, pastBestBefore, cookConfirmTitle, cookConfirmMessage, cookConfirm, cookDecline,
        addMissingToMarket, autoAddToggle, autoAddFooter, lowStockToggle, dateReminderToggle,
        dateReminderScheduleToggle, dateReminderFooter, notificationPermissionDenied, lowStockNoticeTitle,
        lowStockNoticeBody(name: "Süt"), reminderBestBefore(name: "Süt", day: "9 Ekim 2026"),
        reminderUseBy(name: "Süt", day: "9 Ekim 2026"),
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

/// Date kind the user copied from the package. `useBy` and `bestBefore` stay distinct.
/// Neither kind is a food-safety verdict.
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

/// Calendar days as `YYYY-MM-DD`. The stored value is the string. A `Date` exists only
/// at the date-picker edge, and it is read back with the same calendar that built it.
enum PantryDay {
    /// Fixed calendar for comparing two calendar-day strings. Not the device zone.
    private static let comparison: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = zone
        }
        return calendar
    }()

    /// `YYYY-MM-DD` when `text` is that day and a real Gregorian date. Otherwise nil.
    static func canonical(_ text: String?) -> String? {
        guard let text, text.count == 10 else { return nil }
        guard date(from: text, calendar: comparison) != nil else { return nil }
        return text
    }

    /// Day count used only to compare two canonical days. Nil when the text is not a day.
    static func ordinal(_ text: String) -> Int? {
        guard let date = date(from: text, calendar: comparison) else { return nil }
        return comparison.ordinality(of: .day, in: .era, for: date)
    }

    static func isBefore(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = ordinal(lhs), let right = ordinal(rhs) else { return false }
        return left < right
    }

    /// Year-month-day of a picker `Date`, using `calendar`. Call this with the calendar
    /// that is showing the picker, then store the string. Do not store the `Date`.
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Temporary picker value for a stored day. Built in `calendar` so the picker shows that day.
    static func date(from text: String, calendar: Calendar = .current) -> Date? {
        let pieces = text.split(separator: "-").compactMap { Int($0) }
        guard text.count == 10, pieces.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = pieces[0]
        parts.month = pieces[1]
        parts.day = pieces[2]
        guard let date = calendar.date(from: parts), string(from: date, calendar: calendar) == text else { return nil }
        return date
    }

    static func format(_ day: String, calendar: Calendar) -> String {
        guard let date = date(from: day, calendar: calendar) else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

enum PantryDateStatus: Equatable, Sendable {
    case none
    case upcoming(daysLeft: Int)
    case approaching(daysLeft: Int)
    /// The entered use-by day is before today. Not a statement that the food is unsafe.
    case pastUseBy(daysAgo: Int)
    /// The entered best-before day is before today. Not a freshness or safety verdict.
    case pastBestBefore(daysAgo: Int)

    static let approachingWindowDays = 3

    /// `day` and `today` are `YYYY-MM-DD`. The device time zone does not change either string.
    static func evaluate(type: PantryDateType?, day: String?, today: String) -> PantryDateStatus {
        guard let day, let dayNumber = PantryDay.ordinal(day), let todayNumber = PantryDay.ordinal(today) else { return .none }
        let distance = dayNumber - todayNumber
        if distance < 0 {
            return (type ?? .bestBefore) == .useBy ? .pastUseBy(daysAgo: -distance) : .pastBestBefore(daysAgo: -distance)
        }
        return distance <= approachingWindowDays ? .approaching(daysLeft: distance) : .upcoming(daysLeft: distance)
    }

    var isPastUseBy: Bool { if case .pastUseBy = self { return true }; return false }
    var isApproaching: Bool { if case .approaching = self { return true }; return false }
}

/// What a household write may do with the date. A legacy instant is not turned into a day.
enum PantryOutboundDate: Equatable, Sendable {
    case send(type: PantryDateType?, day: String?)
    case omit

    var sendsDate: Bool {
        if case .omit = self { return false }
        return true
    }

    var dateType: PantryDateType? {
        if case .send(let type, _) = self { return type }
        return nil
    }

    var dateValue: String? {
        if case .send(_, let day) = self { return day }
        return nil
    }

    /// `calendarDay` is the stored `YYYY-MM-DD`. `hasLegacyInstant` means the old `Date` column is set.
    static func make(calendarDay: String?, dateType: PantryDateType?, hasLegacyInstant: Bool) -> PantryOutboundDate {
        if let day = PantryDay.canonical(calendarDay), let dateType {
            return .send(type: dateType, day: day)
        }
        if hasLegacyInstant {
            return .omit
        }
        return .send(type: nil, day: nil)
    }
}

/// Household cache dates come from the server string. The old local instant is not an input.
enum PantryHouseholdDate {
    static func canonicalDay(serverDateValue: String?) -> String? {
        PantryDay.canonical(serverDateValue)
    }
}

/// One personal row as the upgrade step sees it. No `Date`, so the step cannot guess a day.
struct LegacyPersonalPantryDateRow: Equatable, Sendable {
    var id: UUID
    var isPersonal: Bool
    var hasLegacyDateInstant: Bool
}

/// Deletes personal rows whose date is still the old `Date`. Dateless personal rows stay.
/// Household rows stay. A second call with `alreadyRan` deletes nothing.
enum LegacyPersonalPantryDatePolicy {
    static let markerKey = "mealroutine.pantry.v51.legacyPersonalDatedRowsRemoved"

    static func rowsToDelete(_ rows: [LegacyPersonalPantryDateRow], alreadyRan: Bool) -> Set<UUID> {
        guard !alreadyRan else { return [] }
        var ids = Set<UUID>()
        for row in rows where row.isPersonal && row.hasLegacyDateInstant {
            ids.insert(row.id)
        }
        return ids
    }
}

/// Date the form loaded. `.legacyInstant` is a household row not yet replaced by the server day.
enum PantryDateAuthority: Equatable, Sendable {
    case day(PantryDateType, String)
    case none
    case legacyInstant
}

/// What save does with the date. `.leave` does not clear and does not invent a day.
enum PantryDateEdit: Equatable, Sendable {
    case set(PantryDateType, String)
    case clear
    case leave

    var storedType: PantryDateType? {
        if case .set(let type, _) = self { return type }
        return nil
    }

    var storedDay: String? {
        if case .set(_, let day) = self { return day }
        return nil
    }
}

enum PantryDateForm {
    static func edit(authority: PantryDateAuthority, hasDate: Bool, type: PantryDateType, pickedDay: String?) -> PantryDateEdit {
        if hasDate, let day = PantryDay.canonical(pickedDay) {
            return .set(type, day)
        }
        if case .legacyInstant = authority {
            return .leave
        }
        return .clear
    }
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
        dateValue: String?,
        sync: PantrySyncMark = .synced,
        today: String,
        calendar: Calendar = .current
    ) -> PantryRowPresentation {
        let amount = QuantityFormat.quantityAndUnit(quantity: quantity, unit: unit)
        let minimum = minimumQuantity.map { "Minimum \(QuantityFormat.quantityAndUnit(quantity: $0, unit: unit))" }
        let status = PantryDateStatus.evaluate(type: dateType, day: dateValue, today: today)
        let type = dateType ?? .bestBefore
        let dateText = dateValue.flatMap { day in
            PantryDay.canonical(day).map { "\(type.title): \(PantryDay.format($0, calendar: calendar))\(relativeSuffix(status))" }
        }

        var badges: [PantryBadge] = []
        switch status {
        case .pastUseBy:
            badges.append(PantryBadge(text: PantryCopy.pastUseBy, symbol: "exclamationmark.octagon.fill", tone: .critical))
        case .pastBestBefore:
            badges.append(PantryBadge(text: PantryCopy.pastBestBefore, symbol: "leaf", tone: .warning))
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

        let spoken = [name, amount, location.title, minimum, dateText].compactMap { $0 } + badges.map { $0.text }
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

// MARK: - Server clock

/// Pantry `createdAt` / `updatedAt` as the server actually sends them.
///
/// Node `Date.toISOString()` (what `server/` writes for every pantry row) is
/// `2026-10-08T07:12:03.123Z` — always three fractional digits, including `.000`.
/// The same instant without a fraction (`2026-10-08T07:12:03Z`) is also accepted,
/// because household routes strip milliseconds. A JSON number is Unix epoch
/// milliseconds, in case a payload is ever emitted that way. Numbers are never
/// what the server sends today.
///
/// A missing timestamp stays missing. Callers must not substitute `.now`: that
/// makes a server row look freshly written and scrambles last-write ordering.
enum PantryServerClock {
    /// Timestamp to store when a server row lands on a cache row that already exists.
    /// No server clock → keep `existing`.
    static func applying(_ server: Date?, keeping existing: Date) -> Date {
        server ?? existing
    }

    /// Timestamp for a cache row that did not exist yet. Unknown server time is the
    /// Unix epoch, not `.now`, so the new row cannot win a last-write comparison by accident.
    static func inserting(_ server: Date?, createdAt: Date?) -> Date {
        server ?? createdAt ?? Date(timeIntervalSince1970: 0)
    }

    /// ISO-8601 UTC with millisecond precision, matching Node `Date.toISOString()`.
    static func string(from date: Date) -> String {
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let instant = Date(timeIntervalSince1970: Double(millis) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        var fraction = Int(millis % 1000)
        if fraction < 0 { fraction += 1000 }
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0,
            fraction
        )
    }

    static func parse(_ text: String) -> Date? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 20, let tIndex = raw.firstIndex(of: "T") else { return nil }
        let body: String
        let offsetSeconds: Int
        if raw.hasSuffix("Z") || raw.hasSuffix("z") {
            body = String(raw.dropLast())
            offsetSeconds = 0
        } else {
            let timePart = raw[raw.index(after: tIndex)...]
            guard let sign = timePart.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
            guard let offset = timeZoneOffsetSeconds(String(raw[sign...])) else { return nil }
            body = String(raw[..<sign])
            offsetSeconds = offset
        }
        let halves = body.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let datePieces = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        guard datePieces.count == 3,
              datePieces[0].count == 4, let year = Int(datePieces[0]),
              datePieces[1].count == 2, let month = Int(datePieces[1]),
              datePieces[2].count == 2, let day = Int(datePieces[2]) else { return nil }
        let timeAndFraction = halves[1].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let clock = timeAndFraction[0].split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 3,
              clock[0].count == 2, let hour = Int(clock[0]),
              clock[1].count == 2, let minute = Int(clock[1]),
              clock[2].count == 2, let second = Int(clock[2]) else { return nil }
        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var fraction = 0.0
        if timeAndFraction.count == 2 {
            let digits = timeAndFraction[1]
            guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) else { return nil }
            guard let value = Double("0." + digits) else { return nil }
            fraction = value
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let utc = calendar.date(from: components) else { return nil }
        return utc.addingTimeInterval(fraction).addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    static func parseEpochMilliseconds(_ value: Double) -> Date? {
        guard value.isFinite else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }

    /// Absent or JSON null → nil. A present value that is not a timestamp throws,
    /// so the row is rejected instead of stored with a made-up clock.
    static func decodeIfPresent<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        if let text = try? container.decode(String.self, forKey: key) {
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Unreadable pantry timestamp '\(text)'. Expected ISO-8601."
                )
            }
            return date
        }
        if let millis = try? container.decode(Double.self, forKey: key) {
            guard let date = parseEpochMilliseconds(millis) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Unreadable pantry epoch milliseconds."
                )
            }
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Pantry timestamp must be an ISO-8601 string or epoch milliseconds."
        )
    }

    static func install(on decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard let date = parse(text) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable pantry timestamp '\(text)'.")
                }
                return date
            }
            if let millis = try? container.decode(Double.self), let date = parseEpochMilliseconds(millis) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Pantry timestamp must be ISO-8601 or epoch milliseconds.")
        }
    }

    private static func timeZoneOffsetSeconds(_ suffix: String) -> Int? {
        guard let signChar = suffix.first, signChar == "+" || signChar == "-" else { return nil }
        let sign = signChar == "+" ? 1 : -1
        let rest = suffix.dropFirst()
        if rest.contains(":") {
            let pieces = rest.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, pieces[0].count == 2, pieces[1].count == 2,
                  let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return sign * (hour * 3600 + minute * 60)
        }
        guard rest.count == 2 || rest.count == 4, rest.allSatisfy({ $0.isNumber }) else { return nil }
        guard let hour = Int(rest.prefix(2)), (0...23).contains(hour) else { return nil }
        var minute = 0
        if rest.count == 4 {
            guard let parsed = Int(rest.suffix(2)), (0...59).contains(parsed) else { return nil }
            minute = parsed
        }
        return sign * (hour * 3600 + minute * 60)
    }
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
    /// Household flag from `0013`. Missing on an older payload means off.
    var autoAddToGrocery: Bool
    var dateType: PantryDateType?
    var dateValue: String?
    /// When false, the server body omits the date keys so a legacy instant is not written back.
    var sendsDate: Bool
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
        autoAddToGrocery: Bool = false,
        dateType: PantryDateType?,
        dateValue: String?,
        version: Int,
        sendsDate: Bool = true,
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
        self.autoAddToGrocery = autoAddToGrocery
        self.dateType = dateType
        self.dateValue = dateValue
        self.sendsDate = sendsDate
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, householdId, ingredientId, displayName, quantity, unit, location, minimumQuantity
        case autoAddToGrocery, dateType, dateValue, sendsDate, version, createdAt, updatedAt
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
        autoAddToGrocery = try container.decodeIfPresent(Bool.self, forKey: .autoAddToGrocery) ?? false
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
        sendsDate = try container.decodeIfPresent(Bool.self, forKey: .sendsDate) ?? true
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? container.decodeIfPresent(Int.self, forKey: .revision)
            ?? 1
        // Not `decode(Date.self)`: `.iso8601` rejects fractional seconds, and `try?`
        // used to turn that into nil. A bad clock fails the row; a missing one stays nil.
        createdAt = try PantryServerClock.decodeIfPresent(container, forKey: .createdAt)
        updatedAt = try PantryServerClock.decodeIfPresent(container, forKey: .updatedAt)
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
        try container.encode(autoAddToGrocery, forKey: .autoAddToGrocery)
        try container.encodeIfPresent(dateType, forKey: .dateType)
        try container.encodeIfPresent(dateValue, forKey: .dateValue)
        if sendsDate == false { try container.encode(false, forKey: .sendsDate) }
        try container.encode(version, forKey: .version)
        if let createdAt { try container.encode(PantryServerClock.string(from: createdAt), forKey: .createdAt) }
        if let updatedAt { try container.encode(PantryServerClock.string(from: updatedAt), forKey: .updatedAt) }
    }
}

/// Body for `POST .../pantry/items` and `PATCH .../pantry/items/:id`. The server schema is strict:
/// `householdId`, `version` and timestamps are never sent, and a cleared date is sent as `null`.
/// `sendsDate == false` omits the date keys so a legacy instant is not written back.
struct PantryItemBody: Encodable, Equatable, Sendable {
    var id: UUID?
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var location: PantryLocation
    var minimumQuantity: Double?
    var autoAddToGrocery: Bool = false
    var dateType: PantryDateType?
    var dateValue: String?
    var confirmSeparate: Bool?
    /// Local only. Not a server field. False omits `dateType` and `dateValue` from the body.
    var sendsDate: Bool = true

    static func create(_ item: PantryRemoteItem, confirmSeparate: Bool) -> PantryItemBody {
        PantryItemBody(
            id: item.id,
            ingredientId: item.ingredientId,
            displayName: item.displayName,
            quantity: item.quantity,
            unit: item.unit,
            location: item.location,
            minimumQuantity: item.minimumQuantity,
            autoAddToGrocery: item.autoAddToGrocery,
            dateType: item.sendsDate && item.dateValue != nil ? item.dateType : nil,
            dateValue: item.sendsDate && item.dateType != nil ? item.dateValue : nil,
            confirmSeparate: confirmSeparate ? true : nil,
            sendsDate: item.sendsDate
        )
    }

    static func patch(_ item: PantryRemoteItem) -> PantryItemBody {
        var body = create(item, confirmSeparate: false)
        body.id = nil
        return body
    }

    private enum CodingKeys: String, CodingKey {
        case id, ingredientId, displayName, quantity, unit, location, minimumQuantity, autoAddToGrocery, dateType, dateValue, confirmSeparate
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
        try container.encode(autoAddToGrocery, forKey: .autoAddToGrocery)
        if sendsDate {
            try container.encode(dateType, forKey: .dateType)
            try container.encode(dateValue, forKey: .dateValue)
        }
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

/// One queued pantry mutation, as conflict resolution sees it.
/// `idempotencyKey` is the work item id. It stays the same when the user reapplies.
struct PantryConflictMutation: Equatable, Sendable {
    var idempotencyKey: UUID
    var action: String
    var householdID: UUID
    var item: PantryRemoteItem?
    var baseVersion: Int?
    var confirmSeparate: Bool
    var serverItem: PantryRemoteItem?
    var serverDeleted: Bool
    var rejection: String?
}

/// The single outbox item "Değişikliğimi yeniden uygula" puts back.
/// `displayQuantity == nil` means the local row is removed (the user was deleting it).
struct PantryReapplyResult: Equatable, Sendable {
    var idempotencyKey: UUID
    var action: String
    var householdID: UUID
    var item: PantryRemoteItem
    var baseVersion: Int?
    var confirmSeparate: Bool
    var displayQuantity: Double?
    var displayRevision: Int
}

/// What "Sunucudaki hali kullan" shows. A nil quantity means the local row goes away.
struct PantryAdoptedServer: Equatable, Sendable {
    var quantity: Double?
    var revision: Int?
}

/// Pure conflict choices for one pantry row. Both keep data: reapply resends the user's
/// latest values on the server version, with the same Idempotency-Key; adopt-server
/// shows the server row and drops the queued edits only because the user asked.
enum PantryConflictResolution {
    static func isConflict(_ mutation: PantryConflictMutation) -> Bool {
        mutation.serverItem != nil || mutation.serverDeleted || mutation.rejection == "pantry_unit_choice"
    }

    /// Nil when there is no user edit or no conflict. The caller must then leave the queue untouched.
    static func reapply(_ mutations: [PantryConflictMutation]) -> PantryReapplyResult? {
        guard let last = mutations.last else { return nil }
        guard let conflict = mutations.first(where: { isConflict($0) }) else { return nil }
        if last.action == "delete" {
            guard let server = conflict.serverItem else { return nil }
            return PantryReapplyResult(
                idempotencyKey: conflict.idempotencyKey,
                action: "delete",
                householdID: last.householdID,
                item: server,
                baseVersion: server.version,
                confirmSeparate: false,
                displayQuantity: nil,
                displayRevision: server.version
            )
        }
        guard var mine = last.item else { return nil }
        if conflict.serverDeleted || conflict.rejection == "pantry_unit_choice" {
            mine.version = 1
            return PantryReapplyResult(
                idempotencyKey: conflict.idempotencyKey,
                action: "create",
                householdID: last.householdID,
                item: mine,
                baseVersion: nil,
                confirmSeparate: true,
                displayQuantity: mine.quantity,
                displayRevision: 1
            )
        }
        guard let server = conflict.serverItem else { return nil }
        mine.version = server.version + 1
        return PantryReapplyResult(
            idempotencyKey: conflict.idempotencyKey,
            action: "update",
            householdID: last.householdID,
            item: mine,
            baseVersion: server.version,
            confirmSeparate: false,
            displayQuantity: mine.quantity,
            displayRevision: server.version + 1
        )
    }

    /// Nil when nothing in the queue is a conflict. The caller drops every queued edit for the row.
    static func adoptServer(_ mutations: [PantryConflictMutation]) -> PantryAdoptedServer? {
        guard let conflict = mutations.first(where: { isConflict($0) }) else { return nil }
        if let server = conflict.serverItem {
            return PantryAdoptedServer(quantity: server.quantity, revision: server.version)
        }
        if conflict.serverDeleted || conflict.rejection == "pantry_unit_choice" {
            return PantryAdoptedServer(quantity: nil, revision: nil)
        }
        return nil
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
    var autoAddToGrocery: Bool
    var hasDate: Bool
    var dateType: PantryDateType
    /// Picker value only. The saved day is `pickedDay`, not this instant.
    var date: Date
    var dateAuthority: PantryDateAuthority

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
        autoAddToGrocery: false,
        hasDate: false,
        dateType: .bestBefore,
        date: Date(timeIntervalSince1970: 0),
        dateAuthority: .none
    )

    static func loaded(
        ingredientId: String? = nil,
        name: String,
        quantity: Double,
        unit: String,
        location: PantryLocation,
        minimumQuantity: Double?,
        autoAddToGrocery: Bool = false,
        dateType: PantryDateType? = nil,
        dateValue: String? = nil,
        dateAuthority: PantryDateAuthority = .none,
        dictionary: IngredientDictionary = .shared,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PantryFormDraft {
        var draft = empty
        draft.date = now
        draft.dateAuthority = dateAuthority
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
        draft.autoAddToGrocery = autoAddToGrocery
        if let day = PantryDay.canonical(dateValue), let picked = PantryDay.date(from: day, calendar: calendar) {
            draft.hasDate = true
            draft.dateType = dateType ?? .bestBefore
            draft.date = picked
            draft.dateAuthority = .day(draft.dateType, day)
        }
        return draft
    }

    /// The calendar day the picker is showing, read with the same calendar the picker uses.
    func pickedDay(calendar: Calendar = .current) -> String? {
        guard hasDate else { return nil }
        return PantryDay.canonical(PantryDay.string(from: date, calendar: calendar))
    }

    func dateEdit(calendar: Calendar = .current) -> PantryDateEdit {
        PantryDateForm.edit(authority: dateAuthority, hasDate: hasDate, type: dateType, pickedDay: pickedDay(calendar: calendar))
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
        calendar: Calendar = .current,
        dictionary: IngredientDictionary = .shared
    ) -> String? {
        guard !stock.isEmpty else { return nil }
        let matches = usable(stock, now: now, calendar: calendar, dictionary: dictionary).filter { candidateKeys(candidate, dictionary).contains($0.key) }
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
        calendar: Calendar = .current,
        dictionary: IngredientDictionary = .shared
    ) -> String {
        guard !stock.isEmpty else { return explanation }
        let notes = candidates.compactMap { self.explanation(candidate: $0, stock: stock, now: now, calendar: calendar, dictionary: dictionary) }
        guard let note = notes.first(where: { $0 == PantryCopy.approachingExpiry }) ?? notes.first else { return explanation }
        if explanation.isEmpty { return note }
        return "\(explanation) \(note)"
    }
}

// MARK: - V5.1 cook, threshold, reminders

/// Opening a plan, checking a line, completing a market row, or regenerating a plan
/// does not deduct. Deduction runs only after the user marks a meal cooked and confirms.
enum PantryStockEvent: String, Equatable, Sendable {
    case openPlanItem
    case checkPlanItem
    case completeMarketRow
    case regeneratePlan
    case markCooked

    static func deducts(_ event: PantryStockEvent, confirmed: Bool) -> Bool {
        event == .markCooked && confirmed
    }
}

/// Low means at or under the minimum, the same line as the "Azaldı" badge.
enum PantryThreshold {
    static func isLow(quantity: Double, minimum: Double?) -> Bool {
        guard let minimum else { return false }
        return quantity <= minimum + 0.000_1
    }

    static func crossedIntoLow(previous: Double, next: Double, minimum: Double?) -> Bool {
        guard let minimum else { return false }
        return previous > minimum + 0.000_1 && next <= minimum + 0.000_1
    }

    static func returnedAbove(previous: Double, next: Double, minimum: Double?) -> Bool {
        guard let minimum else { return false }
        return previous <= minimum + 0.000_1 && next > minimum + 0.000_1
    }

    static func shortfall(quantity: Double, minimum: Double?) -> Double {
        guard let minimum else { return 0 }
        return PantryUnitPolicy.snap(max(0, minimum - max(0, quantity)))
    }
}

struct PantryMarketRow: Equatable, Sendable {
    var itemKey: String
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var isChecked: Bool
    var revision: Int
}

struct PantryGroceryMutation: Equatable, Sendable {
    var itemKey: String
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    /// 0 when the row does not exist yet.
    var baseRevision: Int
    var crossingKey: String
    var creates: Bool
}

enum PantryAutoGrocery {
    /// One replenishment row per ingredient and canonical unit. Meal-plan rows use a
    /// different key and are left alone, including when they are checked.
    static func itemKey(ingredientId: String, unit: String) -> String {
        "pantry-auto:\(ingredientId)|\(GroceryMerger.normalize(unit))"
    }

    static func crossingKey(itemId: String, version: Int) -> String {
        "low:\(itemId)#\(version)"
    }

    /// Applies a set-quantity mutation. The same target twice does not grow the row.
    /// A checked row with this key is returned unchanged and no second row is added.
    static func reduce(_ rows: [PantryMarketRow], _ mutation: PantryGroceryMutation) -> [PantryMarketRow] {
        guard mutation.quantity > 0 else { return rows }
        if let index = rows.firstIndex(where: { $0.itemKey == mutation.itemKey }) {
            var copy = rows
            if copy[index].isChecked { return copy }
            copy[index].quantity = PantryUnitPolicy.snap(mutation.quantity)
            copy[index].unit = GroceryMerger.normalize(mutation.unit)
            copy[index].displayName = mutation.displayName
            return copy
        }
        var copy = rows
        copy.append(PantryMarketRow(
            itemKey: mutation.itemKey,
            ingredientId: mutation.ingredientId,
            displayName: mutation.displayName,
            quantity: PantryUnitPolicy.snap(mutation.quantity),
            unit: GroceryMerger.normalize(mutation.unit),
            isChecked: false,
            revision: 0
        ))
        return copy
    }

    /// Plans the replenishment for one crossing. `applied` remembers crossings so a
    /// retry on this phone does not write again. Two phones that have not seen each
    /// other still propose the same key and the same absolute shortfall.
    static func plan(
        itemId: String,
        ingredientId: String,
        displayName: String,
        previousQuantity: Double,
        nextQuantity: Double,
        unit: String,
        minimum: Double?,
        autoAdd: Bool,
        version: Int,
        rows: [PantryMarketRow],
        applied: Set<String>
    ) -> (mutation: PantryGroceryMutation?, applied: Set<String>) {
        let crossing = crossingKey(itemId: itemId, version: version)
        guard autoAdd, PantryThreshold.crossedIntoLow(previous: previousQuantity, next: nextQuantity, minimum: minimum) else {
            return (nil, applied)
        }
        if applied.contains(crossing) { return (nil, applied) }
        var nextApplied = applied
        nextApplied.insert(crossing)
        let missing = PantryThreshold.shortfall(quantity: nextQuantity, minimum: minimum)
        guard missing > 0 else { return (nil, nextApplied) }
        let key = itemKey(ingredientId: ingredientId, unit: unit)
        if let existing = rows.first(where: { $0.itemKey == key }), existing.isChecked {
            return (nil, nextApplied)
        }
        let canonical = GroceryMerger.normalize(unit)
        let base = rows.first(where: { $0.itemKey == key })?.revision ?? 0
        let mutation = PantryGroceryMutation(
            itemKey: key,
            ingredientId: ingredientId,
            displayName: displayName,
            quantity: missing,
            unit: canonical,
            baseRevision: base,
            crossingKey: crossing,
            creates: rows.contains(where: { $0.itemKey == key }) == false
        )
        return (mutation, nextApplied)
    }
}

struct LowStockNotice: Equatable, Sendable {
    var itemId: String
    var identifier: String
    var title: String
    var body: String
}

enum PantryLowStockNotifications {
    static func identifier(itemId: String) -> String { "pantry-low.\(itemId)" }

    /// `armed` holds items already notified for the current low episode.
    /// The episode is recorded even when notifications are off, so turning them on
    /// while the row is already low does not fire until it rises and falls again.
    static func step(
        itemId: String,
        name: String,
        previousQuantity: Double,
        nextQuantity: Double,
        minimum: Double?,
        enabled: Bool,
        armed: Set<String>
    ) -> (notice: LowStockNotice?, armed: Set<String>) {
        var nextArmed = armed
        if PantryThreshold.returnedAbove(previous: previousQuantity, next: nextQuantity, minimum: minimum) {
            nextArmed.remove(itemId)
            return (nil, nextArmed)
        }
        guard PantryThreshold.crossedIntoLow(previous: previousQuantity, next: nextQuantity, minimum: minimum) else {
            if PantryThreshold.isLow(quantity: nextQuantity, minimum: minimum) {
                nextArmed.insert(itemId)
            }
            return (nil, nextArmed)
        }
        let already = nextArmed.contains(itemId)
        nextArmed.insert(itemId)
        guard enabled, !already else { return (nil, nextArmed) }
        return (LowStockNotice(
            itemId: itemId,
            identifier: identifier(itemId: itemId),
            title: PantryCopy.lowStockNoticeTitle,
            body: PantryCopy.lowStockNoticeBody(name: name)
        ), nextArmed)
    }
}

struct PantryDateReminderSchedule: Equatable, Codable, Sendable {
    var enabled: Bool
    var bestBeforeDaysBefore: [Int]
    var useByDaysBefore: [Int]

    static let standard = PantryDateReminderSchedule(enabled: true, bestBeforeDaysBefore: [2, 0], useByDaysBefore: [1, 0])

    func days(for type: PantryDateType) -> [Int] {
        let raw = type == .useBy ? useByDaysBefore : bestBeforeDaysBefore
        return Array(Set(raw.filter { $0 >= 0 })).sorted(by: >)
    }
}

struct PantryNotificationPreferences: Equatable, Codable, Sendable {
    var lowStockNotificationsEnabled: Bool
    var dateReminderEnabled: Bool
    var dateReminderSchedule: PantryDateReminderSchedule

    static let off = PantryNotificationPreferences(
        lowStockNotificationsEnabled: false,
        dateReminderEnabled: false,
        dateReminderSchedule: .standard
    )
}

enum PantryNotificationPreferenceStore {
    static let key = "mealroutine.pantry.notificationPreferences"

    static func load(_ defaults: UserDefaults = .standard) -> PantryNotificationPreferences {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(PantryNotificationPreferences.self, from: data) else { return .off }
        return stored
    }

    static func save(_ preferences: PantryNotificationPreferences, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}

struct PantryReminderFire: Equatable, Sendable {
    var identifier: String
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var timeZoneIdentifier: String
    var title: String
    var body: String
}

enum PantryDateReminders {
    static let fireHour = 9
    static let fireMinute = 0
    /// Household timezone is not stored. V5.1 fires on the calendar day in the device zone.
    /// `AUD-GLOB-001` keeps a household timezone for V7.

    static func identifier(itemId: String, type: PantryDateType, daysBefore: Int) -> String {
        "pantry-date.\(itemId).\(type.rawValue).\(daysBefore)"
    }

    static func allIdentifiers(itemId: String) -> [String] {
        PantryDateType.allCases.flatMap { type in
            [0, 1, 2].map { identifier(itemId: itemId, type: type, daysBefore: $0) }
        }
    }

    static func plan(
        itemId: String,
        displayName: String,
        dateType: PantryDateType?,
        dateValue: String?,
        quantity: Double,
        remindersEnabled: Bool,
        schedule: PantryDateReminderSchedule,
        timeZone: TimeZone
    ) -> [PantryReminderFire] {
        guard remindersEnabled, schedule.enabled, quantity > 0, let dateType, let day = PantryDay.canonical(dateValue) else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let anchor = PantryDay.date(from: day, calendar: calendar) else { return [] }
        let zone = timeZone.identifier
        return schedule.days(for: dateType).compactMap { lead in
            guard let fire = calendar.date(byAdding: .day, value: -lead, to: anchor) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: fire)
            guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { return nil }
            let when = lead == 0 ? "bugün" : (lead == 1 ? "yarın" : "\(lead) gün içinde")
            let body = dateType == .useBy
                ? PantryCopy.reminderUseBy(name: displayName, day: when)
                : PantryCopy.reminderBestBefore(name: displayName, day: when)
            return PantryReminderFire(
                identifier: identifier(itemId: itemId, type: dateType, daysBefore: lead),
                year: year, month: month, day: dayNumber,
                hour: fireHour, minute: fireMinute,
                timeZoneIdentifier: zone,
                title: PantryCopy.lowStockNoticeTitle,
                body: body
            )
        }
    }
}

struct PantryCookNeed: Equatable, Sendable {
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
}

struct PantryCookStock: Equatable, Sendable, Identifiable {
    var id: String
    var ingredientId: String
    var displayName: String
    var quantity: Double
    var unit: String
    var minimumQuantity: Double?
    var autoAddToGrocery: Bool
    var version: Int
    var dateType: PantryDateType? = nil
    var dateValue: String? = nil

    var identifier: String { id }
}

struct PantryCookPreviewLine: Equatable, Sendable, Identifiable {
    var ingredientId: String
    var displayName: String
    var needed: String
    var stock: String
    var note: String
    var id: String { "\(ingredientId)|\(needed)" }
}

struct PantryCookDeduction: Equatable, Sendable {
    var itemId: String
    var ingredientId: String
    var newQuantity: Double
    var unit: String
    var baseVersion: Int
    var deducted: Double
}

struct PantryCookSkip: Equatable, Sendable {
    var ingredientId: String
    var displayName: String
    var reason: String
}

struct PantryCookShortage: Equatable, Sendable, Identifiable {
    var ingredientId: String
    var displayName: String
    var missingQuantity: Double
    var unit: String
    var autoAddToGrocery: Bool
    var offerAddMissing: Bool
    var id: String { "\(ingredientId)|\(unit)|\(missingQuantity)" }
}

struct PantryCookOutcome: Equatable, Sendable {
    var deductions: [PantryCookDeduction]
    var skipped: [PantryCookSkip]
    var shortages: [PantryCookShortage]
    var groceryMutations: [PantryGroceryMutation]
    var stock: [PantryCookStock]
    var rows: [PantryMarketRow]
    var appliedMeals: Set<String>
    var appliedCrossings: Set<String>
    var armedLow: Set<String>
    var notices: [LowStockNotice]
}

enum PantryCookConsumption {
    static func preview(
        needs: [PantryCookNeed],
        stock: [PantryCookStock],
        dictionary: IngredientDictionary = .shared
    ) -> [PantryCookPreviewLine] {
        let working = stock
        return needs.map { need in
            let needed = QuantityFormat.quantityAndUnit(quantity: need.quantity, unit: need.unit)
            guard let match = match(need, in: working, dictionary: dictionary) else {
                let same = working.contains { sameIngredient($0.ingredientId, need.ingredientId, dictionary: dictionary) }
                let stockText = same ? PantryCopy.unitMismatch : PantryCopy.missingPantry
                return PantryCookPreviewLine(ingredientId: need.ingredientId, displayName: need.displayName, needed: needed, stock: stockText, note: stockText)
            }
            let have = QuantityFormat.quantityAndUnit(quantity: match.quantity, unit: match.unit)
            let note: String
            if let available = PantryUnitPolicy.converted(match.quantity, from: match.unit, to: need.unit), available + 0.000_1 >= need.quantity {
                note = "Evde yeterli"
            } else {
                note = "Stok kadar düşülür"
            }
            return PantryCookPreviewLine(ingredientId: need.ingredientId, displayName: need.displayName, needed: needed, stock: have, note: note)
        }
    }

    static func apply(
        event: PantryStockEvent,
        confirmed: Bool,
        mealId: String,
        needs: [PantryCookNeed],
        stock: [PantryCookStock],
        rows: [PantryMarketRow],
        appliedMeals: Set<String>,
        appliedCrossings: Set<String>,
        armedLow: Set<String>,
        lowStockEnabled: Bool,
        dictionary: IngredientDictionary = .shared
    ) -> PantryCookOutcome {
        guard PantryStockEvent.deducts(event, confirmed: confirmed), !appliedMeals.contains(mealId) else {
            return PantryCookOutcome(
                deductions: [], skipped: [], shortages: [], groceryMutations: [],
                stock: stock, rows: rows, appliedMeals: appliedMeals, appliedCrossings: appliedCrossings,
                armedLow: armedLow, notices: []
            )
        }
        var working = stock
        var deductions: [PantryCookDeduction] = []
        var skipped: [PantryCookSkip] = []
        var shortages: [PantryCookShortage] = []
        var mutations: [PantryGroceryMutation] = []
        var crossings = appliedCrossings
        var rowsNow = rows
        var armed = armedLow
        var notices: [LowStockNotice] = []
        var meals = appliedMeals
        meals.insert(mealId)

        for need in needs where need.quantity > 0 {
            guard let index = working.firstIndex(where: { sameIngredient($0.ingredientId, need.ingredientId, dictionary: dictionary) && PantryUnitPolicy.compatible($0.unit, need.unit) }) else {
                let same = working.contains { sameIngredient($0.ingredientId, need.ingredientId, dictionary: dictionary) }
                skipped.append(PantryCookSkip(
                    ingredientId: need.ingredientId,
                    displayName: need.displayName,
                    reason: same ? PantryCopy.unitMismatch : PantryCopy.missingPantry
                ))
                shortages.append(PantryCookShortage(
                    ingredientId: need.ingredientId,
                    displayName: need.displayName,
                    missingQuantity: PantryUnitPolicy.snap(need.quantity),
                    unit: GroceryMerger.normalize(need.unit),
                    autoAddToGrocery: false,
                    offerAddMissing: true
                ))
                continue
            }
            let row = working[index]
            let neededInStock = PantryUnitPolicy.converted(need.quantity, from: need.unit, to: row.unit) ?? 0
            let taken = min(max(0, row.quantity), neededInStock)
            let remaining = PantryUnitPolicy.snap(max(0, row.quantity - taken))
            if taken > 0 {
                deductions.append(PantryCookDeduction(
                    itemId: row.id,
                    ingredientId: row.ingredientId,
                    newQuantity: remaining,
                    unit: row.unit,
                    baseVersion: row.version,
                    deducted: PantryUnitPolicy.snap(taken)
                ))
                let previous = row.quantity
                working[index].quantity = remaining
                working[index].version = row.version + 1
                let low = PantryLowStockNotifications.step(
                    itemId: row.id, name: row.displayName, previousQuantity: previous, nextQuantity: remaining,
                    minimum: row.minimumQuantity, enabled: lowStockEnabled, armed: armed
                )
                armed = low.armed
                if let notice = low.notice { notices.append(notice) }
                let replenish = PantryAutoGrocery.plan(
                    itemId: row.id, ingredientId: row.ingredientId, displayName: row.displayName,
                    previousQuantity: previous, nextQuantity: remaining, unit: row.unit,
                    minimum: row.minimumQuantity, autoAdd: row.autoAddToGrocery, version: working[index].version,
                    rows: rowsNow, applied: crossings
                )
                crossings = replenish.applied
                if let mutation = replenish.mutation {
                    mutations.append(mutation)
                    rowsNow = PantryAutoGrocery.reduce(rowsNow, mutation)
                }
            }
            let covered = PantryUnitPolicy.converted(taken, from: row.unit, to: need.unit) ?? 0
            let gap = PantryUnitPolicy.snap(max(0, need.quantity - covered))
            if gap > 0 {
                shortages.append(PantryCookShortage(
                    ingredientId: need.ingredientId,
                    displayName: need.displayName,
                    missingQuantity: gap,
                    unit: GroceryMerger.normalize(need.unit),
                    autoAddToGrocery: row.autoAddToGrocery,
                    offerAddMissing: !row.autoAddToGrocery
                ))
                if row.autoAddToGrocery {
                    let cookKey = "cook:\(mealId):\(row.ingredientId)|\(GroceryMerger.normalize(need.unit))"
                    if !crossings.contains(cookKey) {
                        crossings.insert(cookKey)
                        let itemKey = "pantry-cook:\(mealId):\(row.ingredientId)|\(GroceryMerger.normalize(need.unit))"
                        if rowsNow.first(where: { $0.itemKey == itemKey })?.isChecked != true {
                            let mutation = PantryGroceryMutation(
                                itemKey: itemKey,
                                ingredientId: row.ingredientId,
                                displayName: need.displayName,
                                quantity: gap,
                                unit: GroceryMerger.normalize(need.unit),
                                baseRevision: rowsNow.first(where: { $0.itemKey == itemKey })?.revision ?? 0,
                                crossingKey: cookKey,
                                creates: rowsNow.contains(where: { $0.itemKey == itemKey }) == false
                            )
                            mutations.append(mutation)
                            rowsNow = PantryAutoGrocery.reduce(rowsNow, mutation)
                        }
                    }
                }
            }
        }
        return PantryCookOutcome(
            deductions: deductions, skipped: skipped, shortages: shortages, groceryMutations: mutations,
            stock: working, rows: rowsNow, appliedMeals: meals, appliedCrossings: crossings,
            armedLow: armed, notices: notices
        )
    }

    private static func match(_ need: PantryCookNeed, in stock: [PantryCookStock], dictionary: IngredientDictionary) -> PantryCookStock? {
        stock.first { sameIngredient($0.ingredientId, need.ingredientId, dictionary: dictionary) && PantryUnitPolicy.compatible($0.unit, need.unit) }
    }

    private static func sameIngredient(_ lhs: String, _ rhs: String, dictionary: IngredientDictionary) -> Bool {
        let left = dictionary.canonicalId(lhs) ?? lhs
        let right = dictionary.canonicalId(rhs) ?? rhs
        return left == right
    }
}

enum PantryStableUUID {
    /// Same name always yields the same id, so a cook retry keeps one Idempotency-Key.
    static func make(_ name: String) -> UUID {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var hash2: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
            hash2 ^= UInt64(byte)
            hash2 = hash2 &* 0x0000_0100_0000_01b3 &+ 0x9e37
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((hash >> (index * 8)) & 0xff)
            bytes[index + 8] = UInt8((hash2 >> (index * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
