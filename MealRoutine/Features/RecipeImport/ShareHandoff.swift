import Foundation
import Observation

/// App Group files the share extension writes before it closes.
/// The main app copies them into SwiftData the next time it is open.
enum RecipeCaptureStore {
    static let appGroupID = "group.com.mealroutine.app"
    static let capturesName = "captures.json"
    static let indexName = "collection-index.json"
    static let imageDirectory = "RecipeImages"

    static func enqueue(_ capture: RecipeCapture) throws {
        var pending = pending()
        pending.removeAll { $0.id == capture.id }
        pending.append(capture)
        try write(pending, name: capturesName)
    }

    static func pending() -> [RecipeCapture] {
        read([RecipeCapture].self, name: capturesName) ?? []
    }

    static func remove(ids: Set<UUID>) {
        let remaining = pending().filter { !ids.contains($0.id) }
        try? write(remaining, name: capturesName)
    }

    static func index() -> [CollectionSourceRecord] {
        read([CollectionSourceRecord].self, name: indexName) ?? []
    }

    static func writeIndex(_ records: [CollectionSourceRecord]) throws {
        try write(records, name: indexName)
    }

    /// Existing collection row for this URL, if the index or a waiting capture already has it.
    static func existingSlug(for rawURL: String?) -> String? {
        guard let rawURL, let key = RecipeSourceService.normalizedKey(rawURL) else { return nil }
        if let record = index().first(where: { $0.normalizedURL == key }) {
            return record.slug
        }
        let waiting = pending().contains { capture in
            guard !capture.allowDuplicate, let other = capture.urlString else { return false }
            return RecipeSourceService.normalizedKey(other) == key
        }
        return waiting ? "pending" : nil
    }

    static func saveImage(_ data: Data, id: UUID) throws -> String {
        let relative = "\(imageDirectory)/\(id.uuidString.lowercased()).jpg"
        let url = try fileURL(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return relative
    }

    static func resolve(_ storedPath: String) -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return try? fileURL(trimmed)
    }

    private static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = try? fileURL(name),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        let url = try fileURL(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL(_ name: String) throws -> URL {
        let root: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            root = group
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = support.appendingPathComponent("MealRoutine", isDirectory: true)
        }
        return root.appendingPathComponent(name)
    }
}

enum RecipeEditorLaunch: Identifiable, Equatable {
    case newRecipe
    case recipe(String)

    var id: String {
        switch self {
        case .newRecipe: "new"
        case .recipe(let slug): "recipe-\(slug)"
        }
    }

    var slug: String? {
        switch self {
        case .newRecipe: nil
        case .recipe(let slug): slug
        }
    }
}

/// Opens a saved recipe or the editor after a share link. Capture files are drained separately.
@MainActor
@Observable
final class CollectionRouter {
    static let shared = CollectionRouter()

    var openSlug: String?
    var editor: RecipeEditorLaunch?
    var pendingCaptureID: UUID?

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "mealroutine" else { return }
        let host = url.host?.lowercased() ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "recipe":
            let slug = items.first { $0.name == "slug" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slug, !slug.isEmpty, slug != "pending" {
                openSlug = slug
            }
        case "complete":
            if let raw = items.first(where: { $0.name == "capture" })?.value {
                pendingCaptureID = UUID(uuidString: raw)
            }
        default:
            break
        }
    }

    func applyDrain(_ mapped: [UUID: String]) {
        guard let id = pendingCaptureID, let slug = mapped[id] else { return }
        editor = .recipe(slug)
        pendingCaptureID = nil
    }
}
