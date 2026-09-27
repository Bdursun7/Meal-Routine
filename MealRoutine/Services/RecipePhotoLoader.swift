import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Disk cache for catalog photos.
///
/// Files live under Caches/RecipePhotos. The system may delete that directory.
/// There is no in-app eviction list. Commons originals are stored as thumbnails
/// instead of the full upload.
enum RecipePhotoDiskCache {
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("RecipePhotos", isDirectory: true)
    }

    static func fileURL(remoteURL: URL, directory: URL) -> URL {
        directory.appendingPathComponent(RecipePhoto.cacheFileName(for: remoteURL))
    }

    static func read(remoteURL: URL, directory: URL) -> Data? {
        let file = fileURL(remoteURL: remoteURL, directory: directory)
        return try? Data(contentsOf: file)
    }

    static func write(_ data: Data, remoteURL: URL, directory: URL) {
        let file = fileURL(remoteURL: remoteURL, directory: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            return
        }
    }

    static func remove(remoteURL: URL, directory: URL) {
        let file = fileURL(remoteURL: remoteURL, directory: directory)
        try? FileManager.default.removeItem(at: file)
    }
}

/// Fetches a catalog photo and stores the bytes for offline use.
///
/// UniTools sends `Cache-Control: public, max-age=0, must-revalidate`, so URLCache
/// (and `AsyncImage`) will not show the file in airplane mode. This loader keeps its
/// own copy and ignores the shared URL cache. A missing or failed fetch returns nil;
/// the screen keeps the placeholder and the rest of the app does not wait on it.
enum RecipePhotoLoader {
    /// Larger than every bundled photo (the biggest is about 220 KB).
    /// Also larger than a 960 px Commons thumbnail, so a full original that slipped
    /// past the rendition step is still refused.
    static let maxBytes = 8_000_000
    /// Visible rows plus a little prefetch. The catalog has 195 photos; opening
    /// Tarifler used to start one request per row with no cap.
    static let maxConcurrentFetches = 3
    /// Cloudflare rejects some default agents. This one is accepted for the catalog JPEGs.
    static let userAgent = "MealRoutine/1.0 (iOS; recipe-photo)"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = maxConcurrentFetches
        // Default waitsForConnectivity is false, so a missing network fails into the placeholder
        // instead of holding the photo task open.
        return URLSession(configuration: configuration)
    }()

    private static let fetchGate = RecipePhotoFetchGate(limit: maxConcurrentFetches)

    static func load(
        remoteURL: URL,
        maxPixel: Int = RecipePhoto.heroMaxPixel,
        session: URLSession = RecipePhotoLoader.session,
        directory: URL = RecipePhotoDiskCache.defaultDirectory()
    ) async -> Data? {
        let fetchURL = RecipePhoto.deliveryURL(for: remoteURL, maxPixel: maxPixel)
        if let cached = await cachedImageData(for: fetchURL, directory: directory) {
            return cached
        }
        return await fetchGate.withSlot {
            if Task.isCancelled { return nil }
            if let cached = await cachedImageData(for: fetchURL, directory: directory) {
                return cached
            }
            return await fetchAndStore(fetchURL, session: session, directory: directory)
        }
    }

    /// Disk hits used to run on the main actor: `load` is async, and the read sat
    /// before the first await, so every visible row read its file during the tab animation.
    private static func cachedImageData(for remoteURL: URL, directory: URL) async -> Data? {
        let limit = maxBytes
        return await Task.detached(priority: .utility) {
            guard let cached = RecipePhotoDiskCache.read(remoteURL: remoteURL, directory: directory),
                  cached.count <= limit,
                  RecipePhoto.isSupportedImageData(cached) else {
                return nil
            }
            return cached
        }.value
    }

    private static func fetchAndStore(
        _ remoteURL: URL,
        session: URLSession,
        directory: URL
    ) async -> Data? {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg, image/png, image/webp, image/gif, */*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return nil }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.url?.scheme?.lowercased() == "https" else {
                return nil
            }
            guard data.count <= maxBytes, RecipePhoto.isSupportedImageData(data) else {
                return nil
            }
            let stored = data
            await Task.detached(priority: .utility) {
                RecipePhotoDiskCache.write(stored, remoteURL: remoteURL, directory: directory)
            }.value
            return data
        } catch {
            return nil
        }
    }
}

/// Caps simultaneous photo downloads. A cache hit does not take a slot.
/// A cancelled row stays in the queue until a slot frees, then hands that slot
/// to the next row. Removing it early can drop the wakeup.
private actor RecipePhotoFetchGate {
    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func withSlot(_ body: @Sendable () async -> Data?) async -> Data? {
        guard await acquire() else { return nil }
        let value = await body()
        release()
        return value
    }

    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if inFlight < limit {
            inFlight += 1
            return true
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        if Task.isCancelled {
            release()
            return false
        }
        return true
    }

    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            inFlight -= 1
        }
    }
}
