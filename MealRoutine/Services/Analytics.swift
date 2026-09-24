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

    static func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        let entry = AnalyticsEntry(name: event.rawValue, properties: sanitized(properties))
        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        lock.unlock()
        writeToSystemLog(entry.name)
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

    private static func writeToSystemLog(_ name: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.mealroutine.app", category: "analytics")
            .info("\(name, privacy: .public)")
        #endif
    }
}
