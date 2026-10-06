import Foundation

/// API address and Google client id. Debug-Local defaults the API to localhost.
enum MealRoutineConfig {
    static let clientAPIVersion = "1"

    static var googleClientMissingMessage: String {
        "Google girişi için iOS istemci kimliği yok. Google Cloud Console’da ücretsiz bir iOS OAuth istemcisi açıp kimliği yapılandırmaya yaz."
    }

    static var googleClientID: String {
        cleaned(Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)
    }

    /// Nil on a paid build that has not set an API address. Debug-Local always has one.
    static var apiBaseURL: URL? {
        if let url = url(from: Bundle.main.object(forInfoDictionaryKey: "MealRoutineAPIBaseURL") as? String) {
            return url
        }
        #if HOUSEHOLD_LOCAL
        return URL(string: "http://localhost:8080")
        #else
        return nil
        #endif
    }

    private static func cleaned(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") { return "" }
        return trimmed
    }

    private static func url(from raw: String?) -> URL? {
        let value = cleaned(raw)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}
