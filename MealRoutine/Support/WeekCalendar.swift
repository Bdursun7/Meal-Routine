import Foundation

/// Monday-start weeks in the household timezone (`RegionalContext`), independent of the device's
/// first weekday and of the device timezone.
enum WeekCalendar {
    static func calendar(_ timeZone: TimeZone = RegionalContext.timeZone) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    static func weekStart(containing date: Date, timeZone: TimeZone = RegionalContext.timeZone) -> Date {
        let calendar = calendar(timeZone)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.startOfDay(for: start)
    }

    static func dayOffset(for date: Date, weekStart: Date, timeZone: TimeZone = RegionalContext.timeZone) -> Int {
        let calendar = calendar(timeZone)
        let start = calendar.startOfDay(for: weekStart)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return min(max(days, 0), 6)
    }

    static func date(weekStart: Date, dayOffset: Int, timeZone: TimeZone = RegionalContext.timeZone) -> Date {
        calendar(timeZone).date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
    }

    /// Localized weekday name for a plan day (0 = Monday).
    static func dayTitle(offset: Int) -> String {
        Weekday(offset: offset).title
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, timeZone: TimeZone = RegionalContext.timeZone) -> Bool {
        calendar(timeZone).isDate(lhs, inSameDayAs: rhs)
    }

    static func shortDate(
        _ date: Date,
        now: Date = .now,
        timeZone: TimeZone = RegionalContext.timeZone,
        locale: Locale = RegionalContext.displayLocale
    ) -> String {
        if isSameDay(date, now, timeZone: timeZone) {
            return L10n.text("date.today", "Bugün")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar(timeZone)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}

/// Plan day of the week. Monday is 0, matching `dayOffset`.
enum Weekday: Int, CaseIterable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    init(offset: Int) {
        self = Weekday(rawValue: ((offset % 7) + 7) % 7) ?? .monday
    }

    var title: String {
        switch self {
        case .monday: return L10n.text("weekday.monday", "Pazartesi")
        case .tuesday: return L10n.text("weekday.tuesday", "Salı")
        case .wednesday: return L10n.text("weekday.wednesday", "Çarşamba")
        case .thursday: return L10n.text("weekday.thursday", "Perşembe")
        case .friday: return L10n.text("weekday.friday", "Cuma")
        case .saturday: return L10n.text("weekday.saturday", "Cumartesi")
        case .sunday: return L10n.text("weekday.sunday", "Pazar")
        }
    }
}

/// Week identity shared with the server: the `YYYY-MM-DD` Monday of the ISO week in the household
/// timezone. Never formatted in UTC or in the device timezone.
enum WeekIdentity {
    static func string(forWeekContaining date: Date, timeZone: TimeZone = RegionalContext.timeZone) -> String {
        dayString(WeekCalendar.weekStart(containing: date, timeZone: timeZone), timeZone: timeZone)
    }

    /// Local calendar date of an instant, `YYYY-MM-DD`.
    static func dayString(_ date: Date, timeZone: TimeZone = RegionalContext.timeZone) -> String {
        let parts = WeekCalendar.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Local Monday 00:00 for a week identity, or nil when the text is not a real Monday.
    static func weekStart(from identity: String, timeZone: TimeZone = RegionalContext.timeZone) -> Date? {
        let fields = identity.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3, identity.count == 10 else { return nil }
        let calendar = WeekCalendar.calendar(timeZone)
        var components = DateComponents()
        components.year = fields[0]
        components.month = fields[1]
        components.day = fields[2]
        guard let date = calendar.date(from: components) else { return nil }
        let start = calendar.startOfDay(for: date)
        guard dayString(start, timeZone: timeZone) == identity, calendar.component(.weekday, from: start) == 2 else { return nil }
        return start
    }
}
