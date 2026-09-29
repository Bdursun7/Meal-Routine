import Foundation
import Observation

/// One shared item waiting for review. The share extension and the app both use this file.
struct SharedImportPayload: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var urlString: String?
    var text: String?
    var sourceHint: String?
    var receivedAt: Date

    init(
        id: UUID = UUID(),
        urlString: String? = nil,
        text: String? = nil,
        sourceHint: String? = nil,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.urlString = urlString
        self.text = text
        self.sourceHint = sourceHint
        self.receivedAt = receivedAt
    }
}

/// App Group inbox. When the group is unavailable the main app still reads its own support folder.
enum ShareHandoff {
    static let appGroupID = "group.com.mealroutine.app"
    static let fileName = "import-inbox.json"
    private static let defaultsKey = "import-inbox"

    static func write(_ payload: SharedImportPayload) throws {
        let data = try JSONEncoder().encode(payload)
        let url = try inboxFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: defaultsKey)
    }

    static func peek() -> SharedImportPayload? {
        if let url = try? inboxFileURL(),
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(SharedImportPayload.self, from: data) {
            return payload
        }
        if let data = UserDefaults(suiteName: appGroupID)?.data(forKey: defaultsKey),
           let payload = try? JSONDecoder().decode(SharedImportPayload.self, from: data) {
            return payload
        }
        return nil
    }

    static func consume() -> SharedImportPayload? {
        let payload = peek()
        if let url = try? inboxFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: defaultsKey)
        return payload
    }

    /// Enough for the share extension, which does not link the recipe parser.
    static func publicHTTPURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.contains(".") == true else { return nil }
        return url
    }

    static func inboxFileURL() throws -> URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group.appendingPathComponent(fileName)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("MealRoutine", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

/// Opens the import sheet when a share lands, including after onboarding.
@MainActor
@Observable
final class ImportInboxRouter {
    static let shared = ImportInboxRouter()

    var presentationID: UUID?
    var payload: SharedImportPayload?

    func refreshFromInbox() {
        guard let payload = ShareHandoff.peek() else { return }
        self.payload = payload
        presentationID = payload.id
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "mealroutine" else { return }
        refreshFromInbox()
    }

    func takePayload() -> SharedImportPayload? {
        let current = payload ?? ShareHandoff.peek()
        _ = ShareHandoff.consume()
        payload = nil
        presentationID = nil
        return current
    }
}
