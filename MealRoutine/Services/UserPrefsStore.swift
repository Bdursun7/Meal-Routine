import Foundation
import SwiftData

enum UserPrefsStore {
    @MainActor
    static func existing(in context: ModelContext) throws -> UserPrefs? {
        let prefs = try context.fetch(FetchDescriptor<UserPrefs>())
        return prefs.sorted { $0.createdAt < $1.createdAt }.first
    }
}
