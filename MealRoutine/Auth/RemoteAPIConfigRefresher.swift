import Foundation

/// Loads the public server-address JSON. A manual address keeps routing;
/// a successful read still refreshes the last-good cache for when the manual
/// address is cleared. Failures leave the cache in place.
enum RemoteAPIConfigRefresher {
    static let minimumInterval: TimeInterval = 15 * 60

    static func refresh(
        force: Bool = false,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        configURL: URL? = MealRoutineConfig.remoteConfigURL
    ) async {
        guard let configURL else { return }
        if !force, let last = defaults.object(forKey: APIBaseURLResolver.fetchedAtKey) as? Date,
           now.timeIntervalSince(last) < minimumInterval {
            return
        }
        var request = URLRequest(url: configURL, timeoutInterval: 4)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            guard let origin = APIBaseURLResolver.parseRemoteConfig(data) else { return }
            defaults.set(origin, forKey: APIBaseURLResolver.cacheKey)
            defaults.set(now, forKey: APIBaseURLResolver.fetchedAtKey)
        } catch {
            return
        }
    }
}
