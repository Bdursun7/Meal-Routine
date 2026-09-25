import Foundation
import SwiftData

/// Loved / Okay / Never again, from onboarding or after cooking.
@Model
final class RecipeFeedback {
    var uuid: UUID
    var recipeSlug: String
    var ratingRaw: String
    var cooked: Bool
    var createdAt: Date
    /// Optional V2 notes. Empty for V1 rows.
    var reasonsRaw: [String] = []

    init(
        uuid: UUID = UUID(),
        recipeSlug: String,
        rating: MealRating,
        cooked: Bool,
        reasons: [FeedbackReason] = [],
        createdAt: Date = .now
    ) {
        self.uuid = uuid
        self.recipeSlug = recipeSlug
        self.ratingRaw = rating.rawValue
        self.cooked = cooked
        self.reasonsRaw = reasons.map(\.rawValue)
        self.createdAt = createdAt
    }

    var rating: MealRating {
        MealRating(rawValue: ratingRaw) ?? .okay
    }

    var reasons: [FeedbackReason] {
        reasonsRaw.compactMap(FeedbackReason.init(rawValue:))
    }
}
