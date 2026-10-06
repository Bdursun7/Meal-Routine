import Foundation
import XCTest
@testable import MealRoutine

/// Hamsi tava's catalog file rejects a 320 px Commons rendition and serves the original.
final class RecipePhotoLoaderTests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    func testListThumbnailFallsBackWhenCommonsRenditionIsRejected() async {
        let hamsi = URL(string: "https://upload.wikimedia.org/wikipedia/commons/b/b3/Hamsi_tava.jpg")!
        let thumb = RecipePhoto.deliveryURL(for: hamsi, maxPixel: RecipePhoto.thumbnailMaxPixel)
        let hero = RecipePhoto.deliveryURL(for: hamsi, maxPixel: RecipePhoto.heroMaxPixel)
        XCTAssertEqual(
            thumb.absoluteString,
            "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Hamsi_tava.jpg/320px-Hamsi_tava.jpg"
        )
        XCTAssertEqual(
            hero.absoluteString,
            "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Hamsi_tava.jpg/960px-Hamsi_tava.jpg"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hamsi-photo-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = stubSession()
        CommonsThumbStub.reset(replies: [
            thumb.absoluteString: .init(status: 400, body: Data("rejected".utf8)),
            hamsi.absoluteString: .init(status: 200, body: jpeg),
        ])

        let loaded = await RecipePhotoLoader.load(
            remoteURL: hamsi,
            maxPixel: RecipePhoto.thumbnailMaxPixel,
            session: session,
            directory: directory
        )
        XCTAssertEqual(loaded, jpeg)
        XCTAssertEqual(CommonsThumbStub.requestedURLs(), [thumb.absoluteString, hamsi.absoluteString])
        XCTAssertEqual(RecipePhotoDiskCache.read(remoteURL: hamsi, directory: directory), jpeg)
        XCTAssertEqual(RecipePhotoDiskCache.read(remoteURL: thumb, directory: directory), jpeg)
        XCTAssertNil(RecipePhotoDiskCache.read(remoteURL: hero, directory: directory))

        CommonsThumbStub.reset(replies: [
            thumb.absoluteString: .init(status: 400, body: Data("rejected".utf8)),
            hamsi.absoluteString: .init(status: 500, body: Data()),
        ])
        let cached = await RecipePhotoLoader.load(
            remoteURL: hamsi,
            maxPixel: RecipePhoto.thumbnailMaxPixel,
            session: session,
            directory: directory
        )
        XCTAssertEqual(cached, jpeg)
        XCTAssertEqual(CommonsThumbStub.requestedURLs(), [])
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommonsThumbStub.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

/// Per-URL replies for the Hamsi fallback. A lock covers the protocol queue and the test.
private final class CommonsThumbStub: URLProtocol {
    struct Reply: Sendable {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var requested: [String] = []

    static func reset(replies: [String: Reply]) {
        lock.lock()
        self.replies = replies
        requested = []
        lock.unlock()
    }

    static func requestedURLs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        Self.lock.lock()
        Self.requested.append(key)
        let reply = Self.replies[key] ?? Reply(status: 500, body: Data())
        Self.lock.unlock()

        let url = request.url ?? URL(string: "https://upload.wikimedia.org/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
