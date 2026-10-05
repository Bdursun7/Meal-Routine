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

    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "igshid", "igsh", "si", "mc_cid", "mc_eid",
    ]
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
        let url = urls.lazy.compactMap { RecipeSourceService.publicURL($0)?.absoluteString }.first
        let title = firstDistinct(titles, ignoring: url)
        let text = firstDistinct(texts, ignoring: url, also: title)
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

    /// A non-http URL is not a recipe title. http(s) links stay on the URL field.
    private static func isBareUnsupportedURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return false
        }
        return scheme != "http" && scheme != "https"
    }
}
