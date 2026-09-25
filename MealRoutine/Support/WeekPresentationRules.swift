import Foundation

/// How Atladım looks on Bu Hafta. The skip itself still only records a memory signal.
enum SkipControlAppearance: Equatable, Sendable {
    /// Accent outline. The evening can still be skipped.
    case idle
    /// Filled accent. This planned meal is already skipped.
    case selected
    /// Cooked, or a save is in flight. Not the skipped treatment.
    case unavailable
}

enum SkipControl {
    /// Cooked evenings do not offer skip. A later cook also clears any stored skip.
    static func showsAffordance(isCooked: Bool) -> Bool {
        !isCooked
    }

    /// Skip is visible only while the meal stays uncooked.
    static func recordsAsSkipped(skippedAt: Date?, cookedAt: Date?) -> Bool {
        skippedAt != nil && cookedAt == nil
    }

    static func appearance(isSkipped: Bool, isCooked: Bool, isWorking: Bool) -> SkipControlAppearance {
        if isCooked {
            return .unavailable
        }
        if isSkipped {
            return .selected
        }
        if isWorking {
            return .unavailable
        }
        return .idle
    }

    static func title(isSkipped: Bool) -> String {
        isSkipped ? "Atlandı" : "Atladım"
    }

    /// Selected skip uses a filled accent control. Idle stays an outline.
    static func usesFilledAccent(_ appearance: SkipControlAppearance) -> Bool {
        appearance == .selected
    }
}

/// Cook confirmation belongs only to an evening on the open week.
enum CookBarGate {
    static func showsCookBar(
        allowsCookBar: Bool,
        plannedMealID: UUID?,
        mealWeekStart: Date?,
        now: Date
    ) -> Bool {
        guard allowsCookBar, plannedMealID != nil, let mealWeekStart else { return false }
        return WeekCalendar.isSameDay(mealWeekStart, WeekCalendar.weekStart(containing: now))
    }
}
