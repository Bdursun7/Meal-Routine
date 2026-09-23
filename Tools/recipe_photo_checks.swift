import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Catalog photo credit, URL policy, and disk-cache checks. No SwiftData, no Xcode.
///
///   Tools/run_recipe_photo_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func checkCatalog() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "MealRoutine/Recipes/recipes.v1.json"))
    let file = try JSONDecoder().decode(RecipeCatalogFile.self, from: data)
    check(file.recipes.count == 125, "catalog recipe count \(file.recipes.count)")

    var withPhoto: [String] = []
    var withoutPhoto: [String] = []
    for recipe in file.recipes {
        let stored = RecipePhoto.persisted(
            url: recipe.photo?.url,
            author: recipe.photo?.author,
            license: recipe.photo?.license
        )
        if recipe.photo == nil {
            withoutPhoto.append(recipe.id)
            check(stored.url.isEmpty && stored.author.isEmpty && stored.license.isEmpty, "\(recipe.id) nil photo stores empty strings")
            continue
        }
        check(!stored.url.isEmpty, "\(recipe.id) photo url empty")
        check(stored.author == recipe.photo?.author, "\(recipe.id) author not copied verbatim")
        check(stored.license == recipe.photo?.license, "\(recipe.id) license not copied verbatim")
        guard let remote = RecipePhoto.remoteURL(from: stored.url) else {
            check(false, "\(recipe.id) photo url is not https")
            continue
        }
        check(remote.scheme == "https", "\(recipe.id) scheme")
        check(remote.host == "theunitools.com", "\(recipe.id) host \(remote.host ?? "")")
        let credit = RecipePhoto.creditLine(author: stored.author, license: stored.license)
        check(credit == "\(stored.author) · \(stored.license)", "\(recipe.id) credit rewrote catalog text")
        withPhoto.append(recipe.id)
    }

    check(withPhoto.count == 103, "photos \(withPhoto.count), expected 103")
    check(withoutPhoto.count == 22, "without photos \(withoutPhoto.count), expected 22")
    check(withPhoto.contains("menemen"), "menemen has a photo")
    check(withoutPhoto.contains("ojja-merguez"), "ojja-merguez has no photo")
    if withPhoto.count != 103 || withoutPhoto.count != 22 {
        fputs("without photo: \(withoutPhoto.joined(separator: ", "))\n", stderr)
    }

    let menemen = file.recipes.first { $0.id == "menemen" }
    check(menemen?.photo?.url == "https://theunitools.com/recipes/menemen.jpg", "menemen url")
    check(menemen?.photo?.author == "E4024", "menemen author")
    check(menemen?.photo?.license == "CC BY-SA 4.0", "menemen license")
    check(
        RecipePhoto.creditLine(author: "E4024", license: "CC BY-SA 4.0") == "E4024 · CC BY-SA 4.0",
        "menemen credit line"
    )

    let frango = file.recipes.first { $0.id == "frango-piri-piri" }
    let frangoAuthor = frango?.photo?.author ?? ""
    let frangoLicense = frango?.photo?.license ?? ""
    let frangoCredit = RecipePhoto.creditLine(author: frangoAuthor, license: frangoLicense)
    check(frangoAuthor.contains("Kolforn@gmail.com"), "frango author kept in catalog")
    check(frangoCredit == "\(frangoAuthor) · \(frangoLicense)", "frango credit is not shortened")
}

private func checkCreditPolicy() {
    check(RecipePhoto.creditLine(author: "", license: "") == nil, "empty credit")
    check(RecipePhoto.creditLine(author: "  ", license: "\n") == nil, "whitespace credit")
    check(RecipePhoto.creditLine(author: "E4024", license: "") == "E4024", "author only")
    check(RecipePhoto.creditLine(author: "", license: "CC0") == "CC0", "license only")
    check(RecipePhoto.creditLine(author: " Ada ", license: " CC0 ") == "Ada · CC0", "trimmed join")

    let verbatim = RecipePhoto.persisted(url: " https://x ", author: " A ", license: " L ")
    check(verbatim.url == " https://x ", "url stored verbatim")
    check(verbatim.author == " A ", "author stored verbatim")
    check(verbatim.license == " L ", "license stored verbatim")
    let missing = RecipePhoto.persisted(url: nil, author: nil, license: nil)
    check(missing.url.isEmpty && missing.author.isEmpty && missing.license.isEmpty, "nil fields")
}

private func checkURLPolicy() {
    check(RecipePhoto.remoteURL(from: "") == nil, "empty url")
    check(RecipePhoto.remoteURL(from: "   ") == nil, "blank url")
    check(RecipePhoto.remoteURL(from: "http://theunitools.com/recipes/menemen.jpg") == nil, "http rejected")
    check(RecipePhoto.remoteURL(from: "file:///tmp/menemen.jpg") == nil, "file url rejected")
    check(RecipePhoto.remoteURL(from: "not a url") == nil, "garbage rejected")
    check(
        RecipePhoto.remoteURL(from: "https://user:secret@theunitools.com/a.jpg") == nil,
        "credentials rejected"
    )
    let trimmed = RecipePhoto.remoteURL(from: " https://theunitools.com/recipes/menemen.jpg ")
    check(trimmed?.absoluteString == "https://theunitools.com/recipes/menemen.jpg", "trimmed https")
}

private func checkImageSniff() {
    check(RecipePhoto.isSupportedImageData(Data([0xFF, 0xD8, 0xFF, 0xD9])), "jpeg")
    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]
    check(RecipePhoto.isSupportedImageData(Data(png)), "png")
    check(RecipePhoto.isSupportedImageData(Data("GIF89a".utf8)), "gif")
    var webp = Data("RIFF".utf8)
    webp.append(contentsOf: [0, 0, 0, 0])
    webp.append(Data("WEBP".utf8))
    check(RecipePhoto.isSupportedImageData(webp), "webp")
    check(!RecipePhoto.isSupportedImageData(Data("<html></html>".utf8)), "html is not an image")
    check(!RecipePhoto.isSupportedImageData(Data()), "empty is not an image")
}

private func checkDiskCache() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("recipe-photo-checks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let remote = URL(string: "https://theunitools.com/recipes/menemen.jpg")!
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    RecipePhotoDiskCache.write(jpeg, remoteURL: remote, directory: directory)
    check(RecipePhotoDiskCache.read(remoteURL: remote, directory: directory) == jpeg, "cache roundtrip")

    let file = RecipePhotoDiskCache.fileURL(remoteURL: remote, directory: directory)
    check(file.lastPathComponent.hasSuffix(".img"), "cache suffix")
    check(!file.lastPathComponent.contains("menemen"), "cache name is not the remote path")
    check(
        file.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path,
        "cache file stays in the directory"
    )

    let sneaky = URL(string: "https://theunitools.com/../../etc/passwd.jpg")!
    let sneakyFile = RecipePhotoDiskCache.fileURL(remoteURL: sneaky, directory: directory)
    check(
        sneakyFile.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path,
        "cache path cannot escape"
    )
    check(!sneakyFile.lastPathComponent.contains("passwd"), "cache name ignores the url path")

    RecipePhotoDiskCache.remove(remoteURL: remote, directory: directory)
    check(RecipePhotoDiskCache.read(remoteURL: remote, directory: directory) == nil, "cache remove")
}

private final class StubPhotoProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var hits = 0
    nonisolated(unsafe) static var lastAgent: String?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.hits += 1
        Self.lastAgent = request.value(forHTTPHeaderField: "User-Agent")
        let url = request.url ?? URL(string: "https://theunitools.com/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubPhotoProtocol.self]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}

private func checkLoader() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("recipe-photo-loader-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = stubSession()
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    let remote = URL(string: "https://theunitools.com/recipes/menemen.jpg")!

    StubPhotoProtocol.status = 200
    StubPhotoProtocol.body = jpeg
    StubPhotoProtocol.hits = 0
    let loaded = await RecipePhotoLoader.load(remoteURL: remote, session: session, directory: directory)
    check(loaded == jpeg, "loader returns jpeg")
    check(StubPhotoProtocol.hits == 1, "loader fetched once")
    check(StubPhotoProtocol.lastAgent == RecipePhotoLoader.userAgent, "loader user agent")
    check(RecipePhotoDiskCache.read(remoteURL: remote, directory: directory) == jpeg, "loader wrote cache")

    StubPhotoProtocol.hits = 0
    let cached = await RecipePhotoLoader.load(remoteURL: remote, session: session, directory: directory)
    check(cached == jpeg, "loader serves disk cache")
    check(StubPhotoProtocol.hits == 0, "cache hit does not use the network")

    let htmlURL = URL(string: "https://theunitools.com/recipes/not-a-photo.jpg")!
    StubPhotoProtocol.status = 200
    StubPhotoProtocol.body = Data("<html>nope</html>".utf8)
    StubPhotoProtocol.hits = 0
    let html = await RecipePhotoLoader.load(remoteURL: htmlURL, session: session, directory: directory)
    check(html == nil, "html body is not a photo")
    check(RecipePhotoDiskCache.read(remoteURL: htmlURL, directory: directory) == nil, "html was not cached")

    let missingURL = URL(string: "https://theunitools.com/recipes/missing.jpg")!
    StubPhotoProtocol.status = 404
    StubPhotoProtocol.body = jpeg
    let missing = await RecipePhotoLoader.load(remoteURL: missingURL, session: session, directory: directory)
    check(missing == nil, "404 is not a photo")
    check(RecipePhotoDiskCache.read(remoteURL: missingURL, directory: directory) == nil, "404 was not cached")

    var oversized = Data(count: RecipePhotoLoader.maxBytes + 1)
    oversized[0] = 0xFF
    oversized[1] = 0xD8
    oversized[2] = 0xFF
    let hugeURL = URL(string: "https://theunitools.com/recipes/huge.jpg")!
    StubPhotoProtocol.status = 200
    StubPhotoProtocol.body = oversized
    let huge = await RecipePhotoLoader.load(remoteURL: hugeURL, session: session, directory: directory)
    check(huge == nil, "oversized body is refused")
    check(RecipePhotoDiskCache.read(remoteURL: hugeURL, directory: directory) == nil, "oversized body was not cached")
}

@main
struct RecipePhotoCheckMain {
    static func main() async {
        do {
            try checkCatalog()
        } catch {
            failures += 1
            fputs("FAIL catalog \(error)\n", stderr)
        }
        checkCreditPolicy()
        checkURLPolicy()
        checkImageSniff()
        checkDiskCache()
        await checkLoader()
        if failures > 0 {
            fputs("\(failures) failed\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("recipe photos: 103 with, 22 without")
    }
}
