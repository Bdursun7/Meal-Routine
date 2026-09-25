import Foundation

/// How firmly a signal should move the plan.
///
/// Loved and Never again are explicit, so they are high immediately.
/// One replace or one cook stays low: a single behavior is not a settled preference.
enum ConfidenceLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum ConfidenceCalculator {
    static func level(for memory: MealMemorySnapshot) -> ConfidenceLevel {
        if memory.neverAgain || memory.lovedCount > 0 {
            return .high
        }
        if memory.timesCooked >= 2
            || memory.timesReplaced >= 2
            || memory.timeConcernCount >= 2
            || memory.difficultyConcernCount >= 2
            || memory.timesSkipped >= 3 {
            return .medium
        }
        return .low
    }

    /// Scales a behavioral point value. Explicit loved and never scores are not passed here.
    static func scale(_ points: Int, confidence: ConfidenceLevel) -> Int {
        let weight: Double
        switch confidence {
        case .low: weight = 0.4
        case .medium: weight = 0.75
        case .high: weight = 1
        }
        return Int((Double(points) * weight).rounded())
    }

    static func replacementConfidence(timesReplaced: Int) -> ConfidenceLevel {
        if timesReplaced >= 3 { return .high }
        if timesReplaced >= 2 { return .medium }
        return .low
    }

    static func cookRepeatConfidence(timesCooked: Int) -> ConfidenceLevel {
        if timesCooked >= 4 { return .high }
        if timesCooked >= 2 { return .medium }
        return .low
    }
}
