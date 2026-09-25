import Foundation

/// One recipe's learned row. The SwiftData `MealMemory` stores the same fields.
struct MealMemorySnapshot: Equatable, Sendable {
    var recipeID: String
    var timesCooked: Int = 0
    var timesReplaced: Int = 0
    var timesSkipped: Int = 0
    var lastCookedAt: Date?
    var lastSelectedAt: Date?
    var lovedCount: Int = 0
    var okayCount: Int = 0
    /// Newest explicit Loved / Okay / Never. Later feedback wins over an older love.
    var latestRating: MealRating? = nil
    var neverAgain: Bool = false
    var timeConcernCount: Int = 0
    var difficultyConcernCount: Int = 0
    var portionConcernCount: Int = 0
    var missingIngredientCount: Int = 0
    var tooManyIngredientCount: Int = 0
    var wouldMakeAgainCount: Int = 0
    var isFavorite: Bool = false
    var discoveryStatus: DiscoveryStatus = .unknown
    var confidence: ConfidenceLevel = .low

    var hasPersonalSignal: Bool {
        timesCooked > 0
            || timesReplaced > 0
            || timesSkipped > 0
            || lovedCount > 0
            || okayCount > 0
            || neverAgain
            || timeConcernCount > 0
            || difficultyConcernCount > 0
            || isFavorite
            || wouldMakeAgainCount > 0
    }
}

/// What happened. `viewed` is reserved and does not change aggregates.
enum MealBehaviorEventType: String, Codable, CaseIterable, Sendable {
    case viewed
    case selected
    case cooked
    case replaced
    case skipped
    case loved
    case okay
    case neverAgain
    case favorited
}

/// Applies one signal onto a snapshot. Explicit feedback is recorded in full.
/// A single replace or a single cook stays a low-confidence signal.
enum MealMemoryReducer {
    static func apply(
        event: MealBehaviorEventType,
        at date: Date,
        reasons: [FeedbackReason] = [],
        to memory: inout MealMemorySnapshot
    ) {
        switch event {
        case .viewed:
            break
        case .selected:
            memory.lastSelectedAt = later(memory.lastSelectedAt, date)
        case .cooked:
            let wasNew = memory.timesCooked == 0 && memory.lovedCount == 0 && !memory.isFavorite
            memory.timesCooked += 1
            memory.lastCookedAt = later(memory.lastCookedAt, date)
            memory.lastSelectedAt = later(memory.lastSelectedAt, date)
            memory.discoveryStatus = wasNew ? .explored : .familiar
        case .replaced:
            memory.timesReplaced += 1
        case .skipped:
            memory.timesSkipped += 1
        case .loved:
            memory.lovedCount += 1
            memory.isFavorite = true
            memory.latestRating = .loved
            if memory.discoveryStatus == .unknown {
                memory.discoveryStatus = memory.timesCooked > 0 ? .familiar : .new
            }
        case .okay:
            memory.okayCount += 1
            memory.latestRating = .okay
        case .neverAgain:
            memory.neverAgain = true
            memory.isFavorite = false
            memory.latestRating = .never
        case .favorited:
            memory.isFavorite = true
        }
        apply(reasons: reasons, to: &memory)
        memory.confidence = ConfidenceCalculator.level(for: memory)
    }

    static func apply(reasons: [FeedbackReason], to memory: inout MealMemorySnapshot) {
        for reason in reasons {
            switch reason {
            case .tooTimeConsuming:
                memory.timeConcernCount += 1
            case .tooDifficult:
                memory.difficultyConcernCount += 1
            case .wouldMakeAgain:
                memory.wouldMakeAgainCount += 1
            case .portionSmall, .portionLarge:
                memory.portionConcernCount += 1
            case .missingIngredients:
                memory.missingIngredientCount += 1
            case .tooManyIngredients:
                memory.tooManyIngredientCount += 1
            }
        }
    }

    static func setFavorite(_ isFavorite: Bool, on memory: inout MealMemorySnapshot) {
        memory.isFavorite = isFavorite
        if !isFavorite, memory.discoveryStatus == .new, memory.timesCooked == 0 {
            memory.discoveryStatus = .unknown
        }
        memory.confidence = ConfidenceCalculator.level(for: memory)
    }

    static func dataPointCount(in memories: [MealMemorySnapshot]) -> Int {
        memories.reduce(0) { partial, memory in
            partial
                + memory.timesCooked
                + memory.timesReplaced
                + memory.timesSkipped
                + memory.lovedCount
                + memory.okayCount
                + (memory.neverAgain ? 1 : 0)
                + memory.timeConcernCount
                + memory.difficultyConcernCount
                + memory.wouldMakeAgainCount
        }
    }

    private static func later(_ existing: Date?, _ next: Date) -> Date {
        guard let existing else { return next }
        return max(existing, next)
    }
}

/// A past rating, detached from SwiftData so checks can rebuild memory.
struct FeedbackSeed: Equatable, Sendable {
    var slug: String
    var rating: MealRating
    var cooked: Bool
    var createdAt: Date
    var reasons: [FeedbackReason] = []
}

/// One-time read of V1 feedback and recent sightings into meal memory.
enum MealMemoryBackfill {
    static func snapshots(
        feedback: [FeedbackSeed],
        sightings: [RecentMealSighting] = []
    ) -> [String: MealMemorySnapshot] {
        var memories: [String: MealMemorySnapshot] = [:]
        let ordered = feedback.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.slug < rhs.slug
        }
        var cookedSlugs: Set<String> = []
        for item in ordered {
            let slug = item.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { continue }
            var memory = memories[slug] ?? MealMemorySnapshot(recipeID: slug)
            if item.cooked {
                MealMemoryReducer.apply(event: .cooked, at: item.createdAt, to: &memory)
                cookedSlugs.insert(slug)
            }
            let event: MealBehaviorEventType
            switch item.rating {
            case .loved: event = .loved
            case .okay: event = .okay
            case .never: event = .neverAgain
            }
            MealMemoryReducer.apply(event: event, at: item.createdAt, reasons: item.reasons, to: &memory)
            memories[slug] = memory
        }
        for sighting in sightings {
            let slug = sighting.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty else { continue }
            var memory = memories[slug] ?? MealMemorySnapshot(recipeID: slug)
            memory.lastSelectedAt = later(memory.lastSelectedAt, sighting.at)
            if sighting.wasCooked, !cookedSlugs.contains(slug) {
                MealMemoryReducer.apply(event: .cooked, at: sighting.at, to: &memory)
                cookedSlugs.insert(slug)
            } else {
                memory.confidence = ConfidenceCalculator.level(for: memory)
            }
            memories[slug] = memory
        }
        return memories
    }

    private static func later(_ existing: Date?, _ next: Date) -> Date {
        guard let existing else { return next }
        return max(existing, next)
    }
}
