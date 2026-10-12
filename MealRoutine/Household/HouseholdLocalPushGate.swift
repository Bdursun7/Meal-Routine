import Foundation

/// Household events that the server sends with APNs are not also scheduled
/// on this phone. Pantry date reminders do not use this gate.
enum HouseholdLocalPushGate {
    static func deliversLocalNotification(testMode: Bool, remoteAPIConfigured: Bool) -> Bool {
        if testMode { return false }
        return !remoteAPIConfigured
    }
}
