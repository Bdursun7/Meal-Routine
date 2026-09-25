import Foundation

struct RecipeRoute: Hashable, Identifiable {
    var slug: String
    var plannedMealUUID: UUID?
    /// Discovery rail that opened this recipe. Nil for the catalog and the week plan.
    /// Kept off the row so analytics do not need a gesture on the `NavigationLink`.
    var discoverySectionID: String? = nil

    var id: String {
        if let plannedMealUUID {
            return "\(slug)-\(plannedMealUUID.uuidString)"
        }
        return slug
    }
}
