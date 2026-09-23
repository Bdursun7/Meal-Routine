import Foundation

/// Remembers plans and cooks after SwiftData drops the row.
///
/// Replacing the week deletes that `PlanWeek` and its `PlannedMeal`s. Değiştir
/// overwrites `recipeSlug` on the slot, so the previous recipe is gone from the
/// store. Cooked `RecipeFeedback` still survives; uncooked plans do not.
/// This log keeps the latest sighting per slug for `MealRecommender.recencyWindowDays`
/// so the next fill still ranks those recipes down.
enum MealExposureLog {
    static let storageKey = "mealroutine.recentMealExposures.v1"

    static func load(from defaults: UserDefaults = .standard) -> [RecentMealSighting] {
        decode(defaults.stringArray(forKey: storageKey) ?? [])
    }

    static func record(
        _ sightings: [RecentMealSighting],
        now: Date,
        defaults: UserDefaults = .standard
    ) {
        let merged = merge(existing: load(from: defaults), additions: sightings, now: now)
        defaults.set(merged.map(encode), forKey: storageKey)
    }

    /// Keeps the sighting with the stronger penalty at `now`, drops anything outside the window,
    /// and returns a stable order so the stored array does not churn.
    static func merge(
        existing: [RecentMealSighting],
        additions: [RecentMealSighting],
        now: Date,
        windowDays: Int = MealRecommender.recencyWindowDays
    ) -> [RecentMealSighting] {
        let window = max(windowDays, 0) * MealRecommender.secondsPerDay
        let cutoff = now.addingTimeInterval(-Double(window))
        var best: [String: RecentMealSighting] = [:]
        for sighting in existing + additions {
            let slug = sighting.slug.trimmingCharacters(in: .whitespacesAndNewlines)
            if slug.isEmpty { continue }
            if sighting.at < cutoff { continue }
            let stored = RecentMealSighting(slug: slug, at: sighting.at, wasCooked: sighting.wasCooked)
            if let current = best[slug] {
                best[slug] = stronger(current, stored, now: now)
            } else {
                best[slug] = stored
            }
        }
        return best.values.sorted { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            return lhs.slug < rhs.slug
        }
    }

    static func encode(_ sighting: RecentMealSighting) -> String {
        let cooked = sighting.wasCooked ? "1" : "0"
        let seconds = Int(sighting.at.timeIntervalSince1970.rounded())
        return "\(sighting.slug)\t\(seconds)\t\(cooked)"
    }

    static func decode(_ lines: [String]) -> [RecentMealSighting] {
        lines.compactMap(decodeLine)
    }

    private static func stronger(
        _ lhs: RecentMealSighting,
        _ rhs: RecentMealSighting,
        now: Date
    ) -> RecentMealSighting {
        let left = MealRecommender.recencyPenalty(for: lhs.slug, recent: [lhs], now: now)
        let right = MealRecommender.recencyPenalty(for: rhs.slug, recent: [rhs], now: now)
        if left != right { return left > right ? lhs : rhs }
        return lhs.at >= rhs.at ? lhs : rhs
    }

    private static func decodeLine(_ line: String) -> RecentMealSighting? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let slug = String(parts[0])
        guard !slug.isEmpty, let seconds = Int(parts[1]) else { return nil }
        let cookedFlag = parts[2]
        guard cookedFlag == "0" || cookedFlag == "1" else { return nil }
        return RecentMealSighting(
            slug: slug,
            at: Date(timeIntervalSince1970: TimeInterval(seconds)),
            wasCooked: cookedFlag == "1"
        )
    }
}
