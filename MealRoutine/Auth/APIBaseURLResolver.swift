import Foundation

/// Picks the API origin. Manual entry wins, then the last gist address that
/// loaded, then a remote payload that has not been stored yet, then the
/// Info.plist value, then the Local-scheme localhost fallback.
enum APIBaseURLResolver {
    static let missingServerMessage = "sunucu adresi yok"
    static let manualKey = "mealroutine.apiBaseURL.manual"
    static let cacheKey = "mealroutine.apiBaseURL.cache"
    static let fetchedAtKey = "mealroutine.apiBaseURL.fetchedAt"

    struct Input: Equatable, Sendable {
        var manual: String?
        var cached: String?
        var remote: String?
        var plist: String?
        var localFallback: String?
    }

    enum Source: String, Equatable, Sendable {
        case manual
        case cache
        case remote
        case plist
        case local
        case none

        var title: String {
            switch self {
            case .manual: "Elle"
            case .cache: "Son iyi adres"
            case .remote: "Uzak JSON"
            case .plist: "Derleme"
            case .local: "Yerel"
            case .none: "Yok"
            }
        }
    }

    struct Resolution: Equatable, Sendable {
        var url: URL?
        var source: Source
    }

    static func resolve(_ input: Input) -> Resolution {
        if let url = normalize(input.manual) { return Resolution(url: url, source: .manual) }
        if let url = normalize(input.cached) { return Resolution(url: url, source: .cache) }
        if let url = normalize(input.remote) { return Resolution(url: url, source: .remote) }
        if let url = normalize(input.plist) { return Resolution(url: url, source: .plist) }
        if let url = normalize(input.localFallback) { return Resolution(url: url, source: .local) }
        return Resolution(url: nil, source: .none)
    }

    /// `https` origin, or `http` only for localhost and 127.0.0.1.
    /// Drops userinfo, path, query, and fragment. Rejects xcconfig placeholders.
    static func normalize(_ raw: String?) -> URL? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        let localHTTP = scheme == "http" && (host == "localhost" || host == "127.0.0.1")
        guard scheme == "https" || localHTTP else { return nil }
        var origin = URLComponents()
        origin.scheme = scheme
        origin.host = host
        origin.port = components.port
        return origin.url
    }

    /// Reads `{ "apiBaseURL": "https://…" }` and returns the normalized origin string.
    static func parseRemoteConfig(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["apiBaseURL"] as? String else {
            return nil
        }
        return normalize(raw)?.absoluteString
    }

    /// A successful gist read replaces the last-good cache, so the next resolve uses it.
    static func cacheAfterRemotePayload(_ data: Data, currentCache: String?) -> String? {
        parseRemoteConfig(data) ?? normalize(currentCache)?.absoluteString
    }
}
