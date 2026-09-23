import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RecipeListViewModel {
    var searchText = ""

    func filtered(_ recipes: [Recipe]) -> [Recipe] {
        let sorted = recipes.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { recipe in
            recipe.displayName.localizedCaseInsensitiveContains(query)
                || recipe.nameEN.localizedCaseInsensitiveContains(query)
                || recipe.country.localizedCaseInsensitiveContains(query)
        }
    }
}
