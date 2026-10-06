import Foundation

/// Where a shared link came from. Metadata only. It never changes planning.
enum RecipeSourcePlatform: String, Codable, CaseIterable, Sendable {
    case website
    case instagram
    case tiktok
    case youtube
    case safari
    case whatsapp
    case telegram
    case messages
    case notes
    case other
    case unknown

    var title: String {
        switch self {
        case .website: "Web sitesi"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .safari: "Safari"
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .messages: "Mesajlar"
        case .notes: "Notlar"
        case .other: "Diğer"
        case .unknown: "Bilinmeyen kaynak"
        }
    }
}

/// OS share payload. This is not a recipe and it is not parsed into ingredients.
struct RecipeCapture: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var urlString: String?
    var title: String?
    var text: String?
    var imagePath: String?
    var sourcePlatformRaw: String
    var capturedAt: Date
    var allowDuplicate: Bool

    init(
        id: UUID = UUID(),
        urlString: String? = nil,
        title: String? = nil,
        text: String? = nil,
        imagePath: String? = nil,
        sourcePlatform: RecipeSourcePlatform = .unknown,
        capturedAt: Date = .now,
        allowDuplicate: Bool = false
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.text = text
        self.imagePath = imagePath
        self.sourcePlatformRaw = sourcePlatform.rawValue
        self.capturedAt = capturedAt
        self.allowDuplicate = allowDuplicate
    }

    var sourcePlatform: RecipeSourcePlatform {
        RecipeSourcePlatform(rawValue: sourcePlatformRaw) ?? .unknown
    }

    var hasContent: Bool {
        let url = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !url.isEmpty || !title.isEmpty || !text.isEmpty || imagePath != nil
    }
}

/// Source metadata only. Does not fetch or reconstruct a recipe.
enum RecipeSourceService {
    /// Comparison key. The stored URL stays the original string used by Open Original.
    static func normalizedKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(),
              host.contains(".") else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        components.scheme = "https"
        components.host = host
        components.fragment = nil
        if let items = components.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if name.hasPrefix("utm_") { return false }
                return !trackingNames.contains(name)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        var path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path
        guard var text = components.string else { return nil }
        if text.hasSuffix("?") { text.removeLast() }
        return text
    }

    static func publicURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.contains(".") == true else { return nil }
        return url
    }

    static func platform(for url: URL) -> RecipeSourcePlatform {
        let host = (url.host ?? "").lowercased()
        if host.contains("instagram.com") { return .instagram }
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("youtube.com") || host == "youtu.be" || host.hasSuffix(".youtube.com") {
            return .youtube
        }
        if host.contains("whatsapp.") || host == "wa.me" { return .whatsapp }
        if host.contains("telegram.") || host == "t.me" { return .telegram }
        return .website
    }

    static func platform(sourceHint: String?, url: URL?) -> RecipeSourcePlatform {
        let hint = (sourceHint ?? "").lowercased()
        if hint.contains("instagram") { return .instagram }
        if hint.contains("tiktok") { return .tiktok }
        if hint.contains("youtube") { return .youtube }
        if hint.contains("whatsapp") { return .whatsapp }
        if hint.contains("telegram") { return .telegram }
        if hint.contains("safari") { return .safari }
        if hint.contains("notes") || hint.contains("notlar") { return .notes }
        if hint.contains("message") || hint.contains("sms") { return .messages }
        if let url { return platform(for: url) }
        return .unknown
    }

    static func displayName(platform: RecipeSourcePlatform, sourceTitle: String, url: String) -> String {
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if platform != .unknown && platform != .website { return platform.title }
        if let host = publicURL(url)?.host?.replacingOccurrences(of: "www.", with: "") , !host.isEmpty {
            return host
        }
        return platform.title
    }

    /// Caps shared with the editor (`RecipeFieldLimits`). This file is also compiled into the
    /// share extension, which does not include the editor model.
    static let captureURLLimit = 500
    static let captureTitleLimit = 80
    static let captureTextLimit = 1000

    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "igshid", "igsh", "si", "mc_cid", "mc_eid",
    ]
}

/// URL, source key, and title identity. Built-in catalog rows are never duplicates.
enum RecipeIdentity {
    struct Candidate: Equatable, Sendable {
        var slug: String
        var title: String
        var sourceURL: String
        var sourceKey: String
        var isBundled: Bool
    }

    static func normalizedTitle(_ raw: String) -> String {
        let lowered = raw.lowercased(with: Locale(identifier: "tr_TR"))
        let folded = lowered
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
        var scalars: [Unicode.Scalar] = []
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !scalars.isEmpty {
                    scalars.append(" ")
                }
                scalars.append(scalar)
                pendingSpace = false
            } else if !scalars.isEmpty {
                pendingSpace = true
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func titlesMatch(_ left: String, _ right: String) -> Bool {
        let a = normalizedTitle(left)
        let b = normalizedTitle(right)
        guard a.count >= 2, a == b else { return false }
        return a != normalizedTitle("Kaydedilen tarif")
    }

    /// Same normalized URL, same non-empty source key, or a near-identical personal title.
    static func duplicateSlug(
        url: String?,
        title: String?,
        sourceKey: String? = nil,
        among candidates: [Candidate],
        excluding slug: String? = nil
    ) -> String? {
        let key = url.flatMap { RecipeSourceService.normalizedKey($0) }
        let identifier = sourceKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wantedTitle = title ?? ""
        for candidate in candidates {
            if candidate.isBundled { continue }
            if let slug, candidate.slug == slug { continue }
            if let key, RecipeSourceService.normalizedKey(candidate.sourceURL) == key {
                return candidate.slug
            }
            if !identifier.isEmpty, candidate.sourceKey == identifier {
                return candidate.slug
            }
        }
        guard !wantedTitle.isEmpty else { return nil }
        for candidate in candidates {
            if candidate.isBundled { continue }
            if let slug, candidate.slug == slug { continue }
            if titlesMatch(candidate.title, wantedTitle) {
                return candidate.slug
            }
        }
        return nil
    }
}

/// One saved source, used by the share extension to spot a duplicate URL.
struct CollectionSourceRecord: Codable, Equatable, Sendable, Identifiable {
    var slug: String
    var title: String
    var normalizedURL: String
    var savedAt: Date

    var id: String { slug }
}

/// Turns whatever the share sheet handed over into one capture. Extra items are ignored.
enum SharePayloadAssembly {
    static func makeCapture(
        urls: [String],
        titles: [String],
        texts: [String],
        imagePath: String?,
        sourceHint: String?
    ) -> RecipeCapture? {
        let url = urls.lazy.compactMap { raw -> String? in
            guard let absolute = RecipeSourceService.publicURL(raw)?.absoluteString else { return nil }
            let clamped = clamp(absolute, RecipeSourceService.captureURLLimit)
            return clamped.isEmpty ? nil : clamped
        }.first
        let title = firstDistinct(titles, ignoring: url).map { clamp($0, RecipeSourceService.captureTitleLimit) }
        let text = firstDistinct(texts, ignoring: url, also: title).map { clamp($0, RecipeSourceService.captureTextLimit) }
        let image = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedImage = (image?.isEmpty == false) ? image : nil
        let capture = RecipeCapture(
            urlString: url,
            title: title,
            text: text,
            imagePath: storedImage,
            sourcePlatform: RecipeSourceService.platform(
                sourceHint: sourceHint,
                url: url.flatMap { RecipeSourceService.publicURL($0) }
            )
        )
        return capture.hasContent ? capture : nil
    }

    private static func firstDistinct(_ values: [String], ignoring url: String?, also other: String? = nil) -> String? {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let url, trimmed == url { continue }
            if let other, trimmed == other { continue }
            if isBareUnsupportedURL(trimmed) { continue }
            return trimmed
        }
        return nil
    }

    private static func clamp(_ raw: String, _ maxCharacters: Int) -> String {
        guard maxCharacters > 0, raw.count > maxCharacters else { return raw }
        return String(raw.prefix(maxCharacters))
    }

    /// A non-http URL is not a recipe title. http(s) links stay on the URL field.
    private static func isBareUnsupportedURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return false
        }
        return scheme != "http" && scheme != "https"
    }
}
