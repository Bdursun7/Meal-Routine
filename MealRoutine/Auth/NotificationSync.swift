import Foundation
import UIKit
import UserNotifications

struct NotificationPreferences: Codable, Equatable, Sendable {
    var masterEnabled: Bool
    var invitesEnabled: Bool
    var weeklyPlanEnabled: Bool
    var mealVetoEnabled: Bool
    var mealReplacementEnabled: Bool
    var planFinalizedEnabled: Bool

    static let enabled = NotificationPreferences(
        masterEnabled: true,
        invitesEnabled: true,
        weeklyPlanEnabled: true,
        mealVetoEnabled: true,
        mealReplacementEnabled: true,
        planFinalizedEnabled: true
    )
}

struct NotificationHTTPClient: Sendable {
    var session: URLSession
    var baseURL: URL
    var accessToken: String

    func load() async throws -> NotificationPreferences {
        try await send(method: "GET", path: "/v1/notifications/preferences", body: nil as NotificationPreferences?)
    }

    func save(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        try await send(method: "PUT", path: "/v1/notifications/preferences", body: preferences)
    }

    func register(token: String, platform: String) async throws {
        let payload = DeviceTokenPayload(token: token, platform: platform)
        let data = try JSONEncoder().encode(payload)
        try await sendRaw(method: "POST", path: "/v1/notifications/tokens", body: data)
    }

    func unregister(token: String) async throws {
        let payload = DeviceTokenDelete(token: token)
        let data = try JSONEncoder().encode(payload)
        try await sendRaw(method: "DELETE", path: "/v1/notifications/tokens", body: data)
    }

    private func send<Body: Encodable>(method: String, path: String, body: Body?) async throws -> NotificationPreferences {
        let encoded: Data?
        if let body {
            encoded = try JSONEncoder().encode(body)
        } else {
            encoded = nil
        }
        let data = try await sendRaw(method: method, path: path, body: encoded)
        return try JSONDecoder().decode(NotificationPreferences.self, from: data)
    }

    private func sendRaw(method: String, path: String, body: Data?) async throws -> Data {
        guard let url = APIClient.url(baseURL: baseURL, path: path) else { throw NotificationSyncError.transport }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(MealRoutineConfig.clientAPIVersion, forHTTPHeaderField: "X-Client-API-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NotificationSyncError.rejected
        }
        return data
    }
}

private struct DeviceTokenPayload: Encodable {
    var token: String
    var platform: String
}

private struct DeviceTokenDelete: Encodable {
    var token: String
}

enum NotificationSyncError: Error {
    case transport
    case rejected
}

@MainActor
@Observable
final class NotificationSync {
    static let shared = NotificationSync()

    private(set) var preferences = NotificationPreferences.enabled
    private(set) var permissionDenied = false
    var message = ""
    private var deviceToken = ""
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = stored
        }
    }

    func load() async {
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = stored
        }
        guard !HouseholdTestMode.shared.isEnabled else { return }
        guard let client = liveClient() else { return }
        do {
            preferences = try await client.load()
            persist()
            message = ""
        } catch {
            message = "Bildirim ayarı okunamadı. Bu telefondaki seçim duruyor."
        }
    }

    func save(_ next: NotificationPreferences, requestPermission: Bool) async {
        preferences = next
        persist()
        if requestPermission {
            await requestPermissionAndRegister()
        }
        guard !HouseholdTestMode.shared.isEnabled else { return }
        guard let client = liveClient() else {
            message = "Giriş yapınca bu ayar hesaba yazılır."
            return
        }
        do {
            preferences = try await client.save(next)
            persist()
            message = ""
        } catch {
            message = "Bildirim ayarı yazılamadı. Bu telefonda duruyor."
        }
    }

    func requestPermissionAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            permissionDenied = !granted
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            permissionDenied = true
        }
    }

    func registerToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return }
        deviceToken = trimmed
        guard !HouseholdTestMode.shared.isEnabled else { return }
        guard let client = liveClient() else { return }
        do {
            try await client.register(token: trimmed, platform: "ios")
        } catch {
            message = "Cihaz bildirime kaydolamadı. Uygulama bildirimsiz çalışır."
        }
    }

    func unregisterCurrentToken() async {
        let token = deviceToken
        deviceToken = ""
        guard token.count >= 8, !HouseholdTestMode.shared.isEnabled, let client = liveClient() else { return }
        try? await client.unregister(token: token)
    }

    private func liveClient() -> NotificationHTTPClient? {
        guard let baseURL = MealRoutineConfig.apiBaseURL,
              let accessToken = AuthServices.sharedTokens.load()?.accessToken else { return nil }
        return NotificationHTTPClient(session: .shared, baseURL: baseURL, accessToken: accessToken)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static let storageKey = "mealroutine.notificationPreferences"
}
