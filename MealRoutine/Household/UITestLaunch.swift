import Foundation

/// Launch argument for the XCUITest target: `-uitest`.
///
/// Mirrors `HouseholdTestLaunch`. The process uses an in-memory SwiftData store,
/// a fixed Istanbul clock, and no household or product network. A normal launch
/// does not pass this argument, so dogfood data stays on disk.
enum UITestLaunch {
    static let argument = "-uitest"
    static let timeZoneIdentifier = "Europe/Istanbul"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Monday 12 October 2026, 09:00 in Europe/Istanbul. Week identity uses this
    /// instant only while `-uitest` is set. A later Mac date still finds the fixture week.
    static var now: Date {
        guard isEnabled else { return Date() }
        return frozenNow
    }

    /// Call before any calendar or `UserDefaults` test flag is read.
    static func install() {
        guard isEnabled else { return }
        if let zone = TimeZone(identifier: timeZoneIdentifier) {
            NSTimeZone.default = zone
        }
        UITestFixture.resetProcessDefaults()
    }

    private static let frozenNow: Date = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let parts = DateComponents(year: 2026, month: 10, day: 12, hour: 9, minute: 0)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 1_760_246_400)
    }()
}

/// The instant week, grocery, and pantry "today" read. Outside `-uitest` this is `Date()`.
enum AppClock {
    static var now: Date { UITestLaunch.now }
}
