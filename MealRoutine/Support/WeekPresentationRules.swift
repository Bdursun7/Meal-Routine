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
    static func appearance(isSkipped: Bool, isCooked: Bool, isWorking: Bool) -> SkipControlAppearance {
        if isSkipped && !isCooked {
            return .selected
        }
        if isCooked || isWorking {
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
