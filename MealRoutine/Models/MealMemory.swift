import Foundation
import SwiftData

/// Local aggregate for one recipe. Built from behavior events. Reset deletes the row.
@Model
final class MealMemory {
    @Attribute(.unique) var recipeSlug: String
    var timesCooked: Int
    var timesReplaced: Int
    var timesSkipped: Int
    var lastCookedAt: Date?
    var lastSelectedAt: Date?
    var lovedCount: Int
    var okayCount: Int
    var latestRatingRaw: String
    var neverAgain: Bool
    var timeConcernCount: Int
    var difficultyConcernCount: Int
    var portionConcernCount: Int
    var missingIngredientCount: Int
    var tooManyIngredientCount: Int
    var wouldMakeAgainCount: Int
    var isFavorite: Bool
    var discoveryStatusRaw: String
    var confidenceRaw: String
    var updatedAt: Date

    init(snapshot: MealMemorySnapshot, updatedAt: Date = .now) {
        recipeSlug = snapshot.recipeID
        timesCooked = snapshot.timesCooked
        timesReplaced = snapshot.timesReplaced
        timesSkipped = snapshot.timesSkipped
        lastCookedAt = snapshot.lastCookedAt
        lastSelectedAt = snapshot.lastSelectedAt
        lovedCount = snapshot.lovedCount
        okayCount = snapshot.okayCount
        latestRatingRaw = snapshot.latestRating?.rawValue ?? ""
        neverAgain = snapshot.neverAgain
        timeConcernCount = snapshot.timeConcernCount
        difficultyConcernCount = snapshot.difficultyConcernCount
        portionConcernCount = snapshot.portionConcernCount
        missingIngredientCount = snapshot.missingIngredientCount
        tooManyIngredientCount = snapshot.tooManyIngredientCount
        wouldMakeAgainCount = snapshot.wouldMakeAgainCount
        isFavorite = snapshot.isFavorite
        discoveryStatusRaw = snapshot.discoveryStatus.rawValue
        confidenceRaw = snapshot.confidence.rawValue
        self.updatedAt = updatedAt
    }

    var snapshot: MealMemorySnapshot {
        MealMemorySnapshot(
            recipeID: recipeSlug,
            timesCooked: timesCooked,
            timesReplaced: timesReplaced,
            timesSkipped: timesSkipped,
            lastCookedAt: lastCookedAt,
            lastSelectedAt: lastSelectedAt,
            lovedCount: lovedCount,
            okayCount: okayCount,
            latestRating: MealRating(rawValue: latestRatingRaw),
            neverAgain: neverAgain,
            timeConcernCount: timeConcernCount,
            difficultyConcernCount: difficultyConcernCount,
            portionConcernCount: portionConcernCount,
            missingIngredientCount: missingIngredientCount,
            tooManyIngredientCount: tooManyIngredientCount,
            wouldMakeAgainCount: wouldMakeAgainCount,
            isFavorite: isFavorite,
            discoveryStatus: DiscoveryStatus(rawValue: discoveryStatusRaw) ?? .unknown,
            confidence: ConfidenceLevel(rawValue: confidenceRaw) ?? .low
        )
    }

    func replace(with snapshot: MealMemorySnapshot, updatedAt: Date = .now) {
        recipeSlug = snapshot.recipeID
        timesCooked = snapshot.timesCooked
        timesReplaced = snapshot.timesReplaced
        timesSkipped = snapshot.timesSkipped
        lastCookedAt = snapshot.lastCookedAt
        lastSelectedAt = snapshot.lastSelectedAt
        lovedCount = snapshot.lovedCount
        okayCount = snapshot.okayCount
        latestRatingRaw = snapshot.latestRating?.rawValue ?? ""
        neverAgain = snapshot.neverAgain
        timeConcernCount = snapshot.timeConcernCount
        difficultyConcernCount = snapshot.difficultyConcernCount
        portionConcernCount = snapshot.portionConcernCount
        missingIngredientCount = snapshot.missingIngredientCount
        tooManyIngredientCount = snapshot.tooManyIngredientCount
        wouldMakeAgainCount = snapshot.wouldMakeAgainCount
        isFavorite = snapshot.isFavorite
        discoveryStatusRaw = snapshot.discoveryStatus.rawValue
        confidenceRaw = snapshot.confidence.rawValue
        self.updatedAt = updatedAt
    }
}
