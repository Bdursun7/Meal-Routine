import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryViewModel {
    @ObservationIgnored private var cachedKey: Int?
    @ObservationIgnored private var cachedSections: [DiscoverySection] = []

    func sections(
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        memories: [MealMemory],
        prefs: UserPrefs?
    ) -> [DiscoverySection] {
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let index = CatalogIndexCache.warm(recipes: recipes, ratings: ratings)
        let key = cacheKey(index: index, ratings: ratings, memories: memories, prefs: prefs)
        if key == cachedKey {
            return cachedSections
        }
        let map = Dictionary(memories.map { ($0.recipeSlug, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let planning = prefs?.planningPreferences ?? PlanningPreferences.standard(
            maxCookMinutes: CookTimeOptions.resolved(prefs?.maxCookMinutes ?? CookTimeOptions.defaultMinutes),
            dislikedIngredientIds: Set(prefs?.dislikedIngredientIds ?? [])
        )
        let built = DiscoverySections.make(candidates: index.candidates, memories: map, preferences: planning)
        cachedKey = key
        cachedSections = built
        return built
    }

    private func cacheKey(
        index: CatalogIndex,
        ratings: [String: MealRating],
        memories: [MealMemory],
        prefs: UserPrefs?
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(index.key)
        for (slug, rating) in ratings.sorted(by: { $0.key < $1.key }) {
            hasher.combine(slug)
            hasher.combine(rating.rawValue)
        }
        for memory in memories.sorted(by: { $0.recipeSlug < $1.recipeSlug }) {
            let snapshot = memory.snapshot
            hasher.combine(snapshot.recipeID)
            hasher.combine(snapshot.timesCooked)
            hasher.combine(snapshot.timesReplaced)
            hasher.combine(snapshot.timesSkipped)
            hasher.combine(snapshot.lastCookedAt?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(snapshot.lastSelectedAt?.timeIntervalSinceReferenceDate ?? -1)
            hasher.combine(snapshot.lovedCount)
            hasher.combine(snapshot.okayCount)
            hasher.combine(snapshot.latestRating?.rawValue)
            hasher.combine(snapshot.neverAgain)
            hasher.combine(snapshot.timeConcernCount)
            hasher.combine(snapshot.difficultyConcernCount)
            hasher.combine(snapshot.wouldMakeAgainCount)
            hasher.combine(snapshot.isFavorite)
            hasher.combine(snapshot.confidence.rawValue)
        }
        if let prefs {
            let planning = prefs.planningPreferences
            hasher.combine(planning.maxCookMinutes)
            hasher.combine(planning.dislikedIngredientIds.sorted())
            hasher.combine(planning.discovery.rawValue)
            hasher.combine(planning.repetition.rawValue)
            hasher.combine(planning.difficulty.rawValue)
            hasher.combine(planning.weekdayStyle.rawValue)
        }
        let day = Calendar.current.startOfDay(for: Date())
        hasher.combine(day.timeIntervalSinceReferenceDate)
        return hasher.finalize()
    }
}
