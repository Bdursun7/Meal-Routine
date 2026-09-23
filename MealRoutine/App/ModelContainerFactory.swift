import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Recipe.self,
            IngredientLine.self,
            RecipeStep.self,
            PlanWeek.self,
            PlannedMeal.self,
            GroceryItem.self,
            UserPrefs.self,
            RecipeFeedback.self,
            CatalogImportState.self,
        ])
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
