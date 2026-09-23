import Foundation

/// One catalog row reduced to the fields the scaffold picker needs.
struct PickerCandidate: Equatable, Sendable {
    var slug: String
    var totalMinutes: Int
    var trDogfoodScore: Int
    var ingredientIds: Set<String>
    var rating: MealRating?
}

/// Deterministic stand-in for the later recommender.
///
/// The full V1 ranker (dislike filter → preference score → recent-meal penalty →
/// diversity → feedback) is not in this scaffold. This picker:
/// drops "never" ratings, disliked ingredients, and meals over the time cap;
/// prefers "loved"; then sorts by the curated TR score and a stable slug.
/// It returns at most five evenings.
enum NaiveMealPicker {
    static let eveningCap = 5

    static func pick(
        candidates: [PickerCandidate],
        evenings: Int,
        maxCookMinutes: Int,
        dislikedIngredientIds: Set<String>,
        excludingSlugs: Set<String> = []
    ) -> [String] {
        let limit = min(max(evenings, 0), eveningCap)
        guard limit > 0 else { return [] }

        let filtered = candidates.filter { candidate in
            candidate.totalMinutes <= maxCookMinutes
                && !excludingSlugs.contains(candidate.slug)
                && candidate.rating != .never
                && candidate.ingredientIds.isDisjoint(with: dislikedIngredientIds)
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsLoved = lhs.rating == .loved
            let rhsLoved = rhs.rating == .loved
            if lhsLoved != rhsLoved { return lhsLoved }
            if lhs.trDogfoodScore != rhs.trDogfoodScore {
                return lhs.trDogfoodScore > rhs.trDogfoodScore
            }
            return lhs.slug < rhs.slug
        }

        return Array(sorted.prefix(limit).map(\.slug))
    }
}
