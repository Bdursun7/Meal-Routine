import Foundation

/// Monday-start weeks, independent of the device's first weekday.
enum WeekCalendar {
    static let dayNames = [
        "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"
    ]

    static func weekStart(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.startOfDay(for: start)
    }

    static func dayOffset(for date: Date, weekStart: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: weekStart)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return min(max(days, 0), 6)
    }

    static func date(weekStart: Date, dayOffset: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
    }

    static func dayTitle(offset: Int) -> String {
        let index = ((offset % 7) + 7) % 7
        return dayNames[index]
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    static func shortDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Bugün"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}
