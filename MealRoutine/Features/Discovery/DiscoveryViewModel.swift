import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryViewModel {
    func sections(
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        memories: [MealMemory],
        prefs: UserPrefs?
    ) -> [DiscoverySection] {
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let catalog = WeekPlanService.pickerCandidates(from: recipes, ratings: ratings)
        let map = Dictionary(memories.map { ($0.recipeSlug, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let planning = prefs?.planningPreferences ?? PlanningPreferences.standard(
            maxCookMinutes: CookTimeOptions.resolved(prefs?.maxCookMinutes ?? CookTimeOptions.defaultMinutes),
            dislikedIngredientIds: Set(prefs?.dislikedIngredientIds ?? [])
        )
        return DiscoverySections.make(candidates: catalog, memories: map, preferences: planning)
    }
}
