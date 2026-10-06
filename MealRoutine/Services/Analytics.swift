import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Checklist events. Values stay short tokens. Nothing here is a name, account, or location.
enum AnalyticsEvent: String, CaseIterable, Sendable {
    case appOpened = "app_opened"
    case onboardingStarted = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case recipeRated = "recipe_rated"
    case recipeLoved = "recipe_loved"
    case recipeDisliked = "recipe_disliked"
    case planGenerated = "plan_generated"
    case planViewed = "plan_viewed"
    case mealReplaced = "meal_replaced"
    case recipeOpened = "recipe_opened"
    case mealCooked = "meal_cooked"
    case mealFeedbackGiven = "meal_feedback_given"
    case groceryOpened = "grocery_opened"
    case groceryItemChecked = "grocery_item_checked"
    case groceryListCompleted = "grocery_list_completed"
    case mealMemoryUpdated = "meal_memory_updated"
    case personalizedRecommendationViewed = "personalized_recommendation_viewed"
    case personalizedRecommendationSelected = "personalized_recommendation_selected"
    case recommendationReasonViewed = "recommendation_reason_viewed"
    case discoveryPreferenceChanged = "discovery_preference_changed"
    case repetitionPreferenceChanged = "repetition_preference_changed"
    case mealPatternViewed = "meal_pattern_viewed"
    case mealMemoryReset = "meal_memory_reset"
    case smartReplacementUsed = "smart_replacement_used"
    case newRecipeCooked = "new_recipe_cooked"
    case familiarRecipeCooked = "familiar_recipe_cooked"
    case recipeQuickSaved = "recipe_quick_saved"
    case recipeCompletionStarted = "recipe_completion_started"
    case recipeCompletionFinished = "recipe_completion_finished"
    case recipeCompletionAbandoned = "recipe_completion_abandoned"
    case recipeAddedManually = "recipe_added_manually"
    case recipeOpenedOriginal = "recipe_opened_original"
    case recipeAddedToPlan = "recipe_added_to_plan"
    case savedRecipeDeleted = "saved_recipe_deleted"
    case savedRecipeDuplicateDetected = "saved_recipe_duplicate_detected"
    case mealSkipped = "meal_skipped"
    case mealVetoed = "meal_vetoed"
    case householdCreated = "household_created"
    case householdJoined = "household_joined"
    case migrationDone = "migration_done"
    case signIn = "sign_in"
    case inviteSent = "invite_sent"
    case inviteAccepted = "invite_accepted"
    case planFinalized = "plan_finalized"
    case syncFailed = "sync_failed"
    case syncRecovered = "sync_recovered"
}

struct AnalyticsEntry: Equatable, Sendable {
    var name: String
    var properties: [String: String]
}

/// Local-only event log. V1 writes `os_log` when the system has it and keeps a short
/// in-memory buffer for debugging. There is no network sink and no third-party SDK.
enum Analytics {
    private static let lock = NSLock()
    private static var buffer: [AnalyticsEntry] = []
    private static var onceKeys: Set<String> = []
    static let capacity = 200
    /// Set by the app when uploads are allowed. Tests and the product-gap tool leave it nil.
    nonisolated(unsafe) static var productSink: (@Sendable (String, [String: String]) -> Void)?

    static func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        let entry = AnalyticsEntry(name: event.rawValue, properties: sanitized(properties))
        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let sink = productSink
        lock.unlock()
        writeToSystemLog(entry.name)
        if let name = ProductEventCatalog.outbound(for: event) {
            sink?(name, entry.properties)
        }
    }

    /// Launch and other events that should not repeat when SwiftUI calls `onAppear` again.
    static func trackOnce(_ event: AnalyticsEvent) {
        lock.lock()
        let already = onceKeys.contains(event.rawValue)
        if !already {
            onceKeys.insert(event.rawValue)
        }
        lock.unlock()
        guard !already else { return }
        track(event)
    }

    static func recent() -> [AnalyticsEntry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    static func resetForTests() {
        lock.lock()
        buffer.removeAll()
        onceKeys.removeAll()
        lock.unlock()
    }

    /// Drops free-text identity fields. Call sites should still avoid sending them.
    static func sanitized(_ properties: [String: String]) -> [String: String] {
        var clean: [String: String] = [:]
        for (key, value) in properties {
            let lowered = key.lowercased()
            if lowered.contains("name")
                || lowered.contains("email")
                || lowered.contains("phone")
                || lowered.contains("address") {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 40 else { continue }
            clean[key] = trimmed
        }
        return clean
    }

    static func setProductSink(_ sink: (@Sendable (String, [String: String]) -> Void)?) {
        lock.lock()
        productSink = sink
        lock.unlock()
    }

    static func resetProductSinkForTests() {
        setProductSink(nil)
    }

    private static func writeToSystemLog(_ name: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.mealroutine.app", category: "analytics")
            .info("\(name, privacy: .public)")
        #endif
    }
}

enum ProductEventCatalog {
    static let names: Set<String> = [
        "onboarding_completed",
        "plan_generated",
        "meal_cooked",
        "meal_skipped",
        "meal_vetoed",
        "meal_replaced",
        "quick_save",
        "household_created",
        "household_joined",
        "migration_done",
        "sign_in",
        "invite_sent",
        "invite_accepted",
        "plan_finalized",
        "grocery_item_checked",
        "sync_failed",
        "sync_recovered",
    ]

    static func outbound(for event: AnalyticsEvent) -> String? {
        switch event {
        case .onboardingCompleted:
            "onboarding_completed"
        case .planGenerated:
            "plan_generated"
        case .mealCooked:
            "meal_cooked"
        case .mealSkipped:
            "meal_skipped"
        case .mealVetoed:
            "meal_vetoed"
        case .mealReplaced:
            "meal_replaced"
        case .recipeQuickSaved:
            "quick_save"
        case .householdCreated:
            "household_created"
        case .householdJoined:
            "household_joined"
        case .migrationDone:
            "migration_done"
        case .signIn:
            "sign_in"
        case .inviteSent:
            "invite_sent"
        case .inviteAccepted:
            "invite_accepted"
        case .planFinalized:
            "plan_finalized"
        case .groceryItemChecked:
            "grocery_item_checked"
        case .syncFailed:
            "sync_failed"
        case .syncRecovered:
            "sync_recovered"
        default:
            nil
        }
    }
}

struct ProductEvent: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var properties: [String: String]
    var occurredAt: String
}

struct ProductEventBatch: Encodable, Sendable {
    var events: [ProductEvent]
}

struct DiagnosticReport: Codable, Equatable, Sendable {
    var kind: String
    var count: Int
    var exceptionType: String?
    var signal: String?
}

struct DiagnosticBatch: Encodable, Sendable {
    var reports: [DiagnosticReport]
}

enum ProductEventQueue {
    static let optOutKey = "mealroutine.analyticsOptOut"
    static let storageKey = "mealroutine.productEvents"
    static let capacity = 50
    static let batchSize = 20
    private static let lock = NSLock()

    static func isOptedOut(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: optOutKey)
    }

    static func setOptedOut(_ optedOut: Bool, defaults: UserDefaults = .standard) {
        defaults.set(optedOut, forKey: optOutKey)
        if optedOut {
            dropAll(defaults: defaults)
        }
    }

    static func enqueue(
        name: String,
        properties: [String: String] = [:],
        now: Date = Date(),
        id: String = UUID().uuidString,
        defaults: UserDefaults = .standard
    ) {
        guard ProductEventCatalog.names.contains(name) else { return }
        guard !isOptedOut(defaults: defaults) else { return }
        let event = ProductEvent(
            id: id,
            name: name,
            properties: productProperties(properties),
            occurredAt: iso(now)
        )
        lock.lock()
        var pending = load(defaults)
        pending.append(event)
        if pending.count > capacity {
            pending.removeFirst(pending.count - capacity)
        }
        save(pending, defaults: defaults)
        lock.unlock()
    }

    static func pending(defaults: UserDefaults = .standard) -> [ProductEvent] {
        lock.lock()
        defer { lock.unlock() }
        return load(defaults)
    }

    static func nextBatch(defaults: UserDefaults = .standard) -> [ProductEvent] {
        Array(pending(defaults: defaults).prefix(batchSize))
    }

    static func markSent(_ ids: [String], defaults: UserDefaults = .standard) {
        let drop = Set(ids)
        lock.lock()
        let left = load(defaults).filter { !drop.contains($0.id) }
        save(left, defaults: defaults)
        lock.unlock()
    }

    static func dropAll(defaults: UserDefaults = .standard) {
        lock.lock()
        defaults.removeObject(forKey: storageKey)
        lock.unlock()
    }

    static func productProperties(_ properties: [String: String]) -> [String: String] {
        let clean = Analytics.sanitized(properties)
        return clean.filter { key, _ in
            let lowered = key.lowercased()
            return !lowered.contains("title")
                && !lowered.contains("note")
                && !lowered.contains("url")
                && !lowered.contains("recipe")
                && !lowered.contains("slug")
                && !lowered.contains("token")
                && !lowered.contains("text")
        }
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func load(_ defaults: UserDefaults) -> [ProductEvent] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ProductEvent].self, from: data)) ?? []
    }

    private static func save(_ events: [ProductEvent], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum DiagnosticQueue {
    static let crashOptInKey = "mealroutine.crashReportsOptIn"
    static let storageKey = "mealroutine.pendingDiagnostics"
    private static let lock = NSLock()

    static func allowsUpload(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: crashOptInKey)
    }

    static func setUploadEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: crashOptInKey)
        if !enabled {
            dropAll(defaults: defaults)
        }
    }

    static func enqueue(_ report: DiagnosticReport, defaults: UserDefaults = .standard) {
        guard allowsUpload(defaults: defaults) else { return }
        guard report.count > 0, report.count <= 1_000 else { return }
        let kind = report.kind
        guard kind == "crash" || kind == "hang" || kind == "cpu" || kind == "disk" || kind == "metric" else { return }
        let clean = DiagnosticReport(
            kind: kind,
            count: report.count,
            exceptionType: shortToken(report.exceptionType),
            signal: shortToken(report.signal)
        )
        lock.lock()
        var pending = load(defaults)
        pending.append(clean)
        if pending.count > 5 {
            pending.removeFirst(pending.count - 5)
        }
        save(pending, defaults: defaults)
        lock.unlock()
    }

    static func pending(defaults: UserDefaults = .standard) -> [DiagnosticReport] {
        lock.lock()
        defer { lock.unlock() }
        return load(defaults)
    }

    static func markSent(defaults: UserDefaults = .standard) {
        dropAll(defaults: defaults)
    }

    static func dropAll(defaults: UserDefaults = .standard) {
        lock.lock()
        defaults.removeObject(forKey: storageKey)
        lock.unlock()
    }

    static func shortToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    private static func load(_ defaults: UserDefaults) -> [DiagnosticReport] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticReport].self, from: data)) ?? []
    }

    private static func save(_ reports: [DiagnosticReport], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
