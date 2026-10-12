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

    /// Resolved origin. Manual entry, then the last gist address, then Info.plist,
    /// then localhost on the Local scheme. Nil means the beta has no server yet.
    static var apiBaseURL: URL? {
        currentResolution().url
    }

    static var remoteConfigURL: URL? {
        APIBaseURLResolver.normalize(Bundle.main.object(forInfoDictionaryKey: "MealRoutineRemoteConfigURL") as? String)
    }

    static func currentResolution(defaults: UserDefaults = .standard) -> APIBaseURLResolver.Resolution {
        #if HOUSEHOLD_LOCAL
        let localFallback = "http://localhost:8080"
        #else
        let localFallback: String? = nil
        #endif
        return APIBaseURLResolver.resolve(
            APIBaseURLResolver.Input(
                manual: defaults.string(forKey: APIBaseURLResolver.manualKey),
                cached: defaults.string(forKey: APIBaseURLResolver.cacheKey),
                remote: nil,
                plist: Bundle.main.object(forInfoDictionaryKey: "MealRoutineAPIBaseURL") as? String,
                localFallback: localFallback
            )
        )
    }

    private static func cleaned(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") { return "" }
        return trimmed
    }
}
