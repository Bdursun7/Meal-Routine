import Foundation

/// How a catalog `photo` object is stored and when it may be shown.
///
/// The strings are copied as shipped. Display joins them; it does not fill in a
/// missing author or license, and it does not swap in a different image URL.
enum RecipePhoto {
    struct Stored: Equatable, Sendable {
        var url: String
        var author: String
        var license: String
    }

    /// Seed mapping. Nil and missing JSON fields become empty strings.
    static func persisted(url: String?, author: String?, license: String?) -> Stored {
        Stored(url: url ?? "", author: author ?? "", license: license ?? "")
    }

    /// Author and license, verbatim, joined only when both are present.
    /// Whitespace-only parts are treated as missing. Returns nil when both are missing.
    static func creditLine(author: String, license: String) -> String? {
        let parts = [author, license]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Hosts the catalog may load a photo from. UniTools JPEGs stay on their own host.
    /// Open-license fills use a direct `upload.wikimedia.org` file or thumbnail.
    static let allowedHosts: Set<String> = [
        "theunitools.com",
        "upload.wikimedia.org",
    ]

    /// HTTPS URL from the catalog photo field.
    /// HTTP, empty strings, credentials, and hosts outside `allowedHosts` stay placeholders.
    static func remoteURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard url.user == nil, url.password == nil else { return nil }
        guard allowedHosts.contains(host) else { return nil }
        return url
    }

    /// JPEG, PNG, GIF, or WebP. HTML error pages are not images.
    static func isSupportedImageData(_ data: Data) -> Bool {
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF {
            return true
        }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if data.count >= png.count, Array(data.prefix(png.count)) == png {
            return true
        }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) {
            return true
        }
        if data.count >= 12,
           data.starts(with: Data("RIFF".utf8)),
           data.subdata(in: 8..<12) == Data("WEBP".utf8) {
            return true
        }
        return false
    }

    /// Cache file name. The remote path is not used, so a URL cannot escape the cache directory.
    static func cacheFileName(for remoteURL: URL) -> String {
        let digest = StableContentHash.fnv1a64Hex(Data(remoteURL.absoluteString.utf8))
        return "\(digest).img"
    }
}
