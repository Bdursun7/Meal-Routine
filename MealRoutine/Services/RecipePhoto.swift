import Foundation

/// How a catalog `photo` object is stored and when it may be shown.
///
/// The strings are copied as shipped. Display joins them; it does not fill in a
/// missing author or license, and it does not replace the catalog photo with a
/// different picture. A Commons download may request a smaller rendition of that
/// same file.
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

    /// Longest edge requested from Commons. The catalog URL is not rewritten in storage;
    /// this is only the bytes we download for the same file.
    static let heroMaxPixel = 960
    static let backdropMaxPixel = 800
    static let thumbnailMaxPixel = 320

    /// Which screen is asking. Tarifler rows stay on the small rendition.
    /// Detail, whether it was opened from Tarifler or Bu Hafta, always uses the hero.
    enum Role: Equatable, Sendable {
        case listThumbnail
        case cardBackdrop
        case detailHero

        var maxPixel: Int {
            switch self {
            case .listThumbnail: RecipePhoto.thumbnailMaxPixel
            case .cardBackdrop: RecipePhoto.backdropMaxPixel
            case .detailHero: RecipePhoto.heroMaxPixel
            }
        }
    }

    /// Point height of the detail hero plate. The bitmap must not change it.
    static let heroPointHeight: Double = 220
    /// Narrowest full-bleed hero (about 320 pt across a 220 pt plate).
    /// A Commons frame is 4:3, which is below this, so that box is not the plate.
    static let heroMinimumAspect: Double = 1.45

    /// Commons (or other) URL and the cache key for one role.
    /// Detail from either tab must pass `.detailHero`, never the list thumbnail.
    static func renditionURL(for remoteURL: URL, role: Role) -> URL {
        deliveryURL(for: remoteURL, maxPixel: role.maxPixel)
    }

    /// True when the plate is the settled frame, so a bitmap can be drawn.
    ///
    /// List measures a hero before the row width is real. A bitmap in that pass is
    /// clipped to a short or square slot and looks cut off; the next pass, often
    /// when the credit line appears, shows the rest of the photo. A zero edge is
    /// also the slot Core Animation refuses to create. Callers keep the placeholder
    /// until this is true.
    ///
    /// `widerThanTall` is the detail hero. The old check only required both edges
    /// to clear 220 pt, so a 4:3 bitmap still passed: the 960×720 rendition, the
    /// 320×240 list thumbnail, and a full upload. Tarifler pushes a list from a
    /// list, and that first measurement is the bitmap, which the row then clips.
    /// Bu Hafta pushes from a scroll view, so the first measurement is already the
    /// plate. The hero now also requires the plate height and a wide-enough frame.
    static func isReadyPhotoSlot(
        width: Double,
        height: Double,
        minimumWidth: Double,
        minimumHeight: Double,
        widerThanTall: Bool
    ) -> Bool {
        guard width.isFinite, height.isFinite, minimumWidth > 1, minimumHeight > 1 else { return false }
        guard width > 1, height > 1 else { return false }
        guard width + 0.5 >= minimumWidth, height + 0.5 >= minimumHeight else { return false }
        if widerThanTall {
            if width <= height { return false }
            if abs(height - minimumHeight) > 1 { return false }
            if width + 0.5 < height * heroMinimumAspect { return false }
        }
        return true
    }

    /// Point size of the hero bitmap when `measured` is the detail plate.
    ///
    /// The hero spinner stays up until this returns a size. Tarifler pushes a
    /// list from a list, so the first width is often the source row (about
    /// 300 pt) or a Commons pixel box (960×720, 320×240). Those must not paint:
    /// the credit line is hidden until the plate is painted, and that line used
    /// to be the only second layout pass. Callers have to measure the detail
    /// list's own 220 pt band, then ask again after the push settles.
    static func heroDrawSize(measuredWidth: Double, measuredHeight: Double) -> (width: Double, height: Double)? {
        guard isReadyPhotoSlot(
            width: measuredWidth,
            height: measuredHeight,
            minimumWidth: heroPointHeight,
            minimumHeight: heroPointHeight,
            widerThanTall: true
        ) else { return nil }
        return (measuredWidth, measuredHeight)
    }

    struct AspectFillRect: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// Where to draw `image` so it fills `slot` and the overflow is centered.
    /// The result is the final crop. It is not the bitmap's own pixel box.
    static func aspectFillRect(
        imageWidth: Double,
        imageHeight: Double,
        slotWidth: Double,
        slotHeight: Double
    ) -> AspectFillRect? {
        let edges = [imageWidth, imageHeight, slotWidth, slotHeight]
        guard edges.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let scale = max(slotWidth / imageWidth, slotHeight / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return AspectFillRect(
            x: (slotWidth - width) / 2,
            y: (slotHeight - height) / 2,
            width: width,
            height: height
        )
    }

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

    /// True when a meal card has a picture to show.
    ///
    /// Catalog rows use an allowed HTTPS url. Personal recipes leave that url empty
    /// and keep the file in `sourceImagePath`. Detail already draws that file.
    static func hasCardPhoto(urlString: String, localImagePath: String) -> Bool {
        if remoteURL(from: urlString) != nil { return true }
        return !localImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A smaller rendition of the same Commons file.
    ///
    /// Seventy-two catalog photos point at the original upload, often around 1 MB.
    /// A list row is 64 points wide, so the original is decoded and thrown away.
    /// UniTools JPEGs are already small and are returned unchanged. An existing
    /// thumbnail wider than `maxPixel` is narrowed. A thumbnail that is already
    /// small enough, or a path this does not recognize, is left alone.
    static func deliveryURL(for remoteURL: URL, maxPixel: Int) -> URL {
        guard maxPixel > 0, remoteURL.host?.lowercased() == "upload.wikimedia.org" else {
            return remoteURL
        }
        guard var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) else {
            return remoteURL
        }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/wikipedia/") else { return remoteURL }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[1] == "wikipedia" else { return remoteURL }

        if parts[3] == "thumb" {
            guard parts.count >= 5 else { return remoteURL }
            let last = parts[parts.count - 1]
            guard let resized = resizedThumbComponent(last, maxPixel: maxPixel), resized != last else {
                return remoteURL
            }
            var updated = parts
            updated[updated.count - 1] = resized
            components.percentEncodedPath = updated.joined(separator: "/")
            return components.url ?? remoteURL
        }

        // /wikipedia/{project}/{hash1}/{hash2}/{file}
        guard parts.count == 6 else { return remoteURL }
        let file = parts[5]
        guard file.contains(".") else { return remoteURL }
        let thumb = "\(maxPixel)px-\(file)"
        let updated = [parts[0], parts[1], parts[2], "thumb", parts[3], parts[4], file, thumb]
        components.percentEncodedPath = updated.joined(separator: "/")
        return components.url ?? remoteURL
    }

    /// `960px-Name.jpg` -> `320px-Name.jpg` when the current width is larger than `maxPixel`.
    private static func resizedThumbComponent(_ last: String, maxPixel: Int) -> String? {
        guard let marker = last.range(of: "px-") else { return nil }
        let widthText = last[..<marker.lowerBound]
        guard let width = Int(widthText), width > 0 else { return nil }
        if width <= maxPixel { return last }
        return "\(maxPixel)px-\(last[marker.upperBound...])"
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
