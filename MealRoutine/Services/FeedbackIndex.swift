import Foundation

enum FeedbackIndex {
    /// Latest rating wins when the same recipe was marked more than once.
    static func latestRatings(in feedback: [RecipeFeedback]) -> [String: MealRating] {
        var latest: [String: (date: Date, rating: MealRating)] = [:]
        for item in feedback {
            let rating = item.rating
            if let existing = latest[item.recipeSlug], existing.date > item.createdAt {
                continue
            }
            latest[item.recipeSlug] = (item.createdAt, rating)
        }
        return latest.mapValues(\.rating)
    }
}
