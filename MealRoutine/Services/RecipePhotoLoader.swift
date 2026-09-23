import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Disk cache for catalog photos.
///
/// Files live under Caches/RecipePhotos. The system may delete that directory.
/// There is no in-app eviction list; a full pass of the catalog is about 14 MB.
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
    static let maxBytes = 8_000_000
    /// Cloudflare rejects some default agents. This one is accepted for the catalog JPEGs.
    static let userAgent = "MealRoutine/1.0 (iOS; recipe-photo)"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        // Default waitsForConnectivity is false, so a missing network fails into the placeholder
        // instead of holding the photo task open.
        return URLSession(configuration: configuration)
    }()

    static func load(
        remoteURL: URL,
        session: URLSession = RecipePhotoLoader.session,
        directory: URL = RecipePhotoDiskCache.defaultDirectory()
    ) async -> Data? {
        if let cached = RecipePhotoDiskCache.read(remoteURL: remoteURL, directory: directory),
           cached.count <= maxBytes,
           RecipePhoto.isSupportedImageData(cached) {
            return cached
        }

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
            RecipePhotoDiskCache.write(data, remoteURL: remoteURL, directory: directory)
            return data
        } catch {
            return nil
        }
    }
}
