import Foundation

struct RecipeRoute: Hashable, Identifiable {
    var slug: String
    var plannedMealUUID: UUID?

    var id: String {
        if let plannedMealUUID {
            return "\(slug)-\(plannedMealUUID.uuidString)"
        }
        return slug
    }
}
