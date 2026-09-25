import Foundation

struct DiscoveryItem: Equatable, Sendable, Identifiable {
    var slug: String
    var reason: String
    var badge: FamiliarityBadge?

    var id: String { slug }
}

struct DiscoverySection: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var items: [DiscoveryItem]
}

/// Capped recipe groups for the Tarifler tab. No infinite rail.
enum DiscoverySections {
    static let sectionLimit = 5

    static func make(
        candidates: [PickerCandidate],
        memories: [String: MealMemorySnapshot],
        preferences: PlanningPreferences,
        now: Date = .now
    ) -> [DiscoverySection] {
        let taste = PersonalizedScoringService.profile(memories: memories, candidates: candidates)
        // No history means no rails. Score each recipe once after that check.
        // Doing it inside `sorted` rebuilds the taste profile on every comparison.
        guard taste.dataPointCount > 0 else { return [] }
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = candidates.filter { candidate in
            PersonalizedScoringService.isEligible(
                candidate,
                preferences: preferences,
                memory: memories[candidate.slug],
                blockedSlugs: [],
                enforceLovedGap: false,
                enforceDifficulty: false,
                now: now
            )
        }
        let ranked = eligible.map { candidate in
            (
                candidate,
                PersonalizedScoringService.listRank(
                    candidate,
                    memory: memories[candidate.slug],
                    taste: taste,
                    catalogBySlug: bySlug,
                    preferences: preferences,
                    now: now
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.slug < rhs.0.slug
        }
        .map(\.0)
        var sections: [DiscoverySection] = []

        let recommended = ranked.prefix(sectionLimit).map {
            item($0, memories: memories, taste: taste, candidates: candidates, hasHistory: true)
        }
        if !recommended.isEmpty {
            sections.append(DiscoverySection(id: "recommended", title: "Sana uygun", items: Array(recommended)))
        }

        let similar = ranked.filter { candidate in
            !taste.lovedSlugs.contains(candidate.slug) && sharesLovedShape(candidate, taste: taste, bySlug: bySlug)
        }
        .prefix(sectionLimit)
        .map { item($0, memories: memories, taste: taste, candidates: candidates, hasHistory: true) }
        if !similar.isEmpty {
            sections.append(DiscoverySection(id: "similar", title: "Sevdiklerine benzer", items: Array(similar)))
        }

        if !taste.triedCategories.isEmpty {
            let different = ranked.filter { candidate in
                let category = candidate.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return RecommendationReasonService.isNew(memories[candidate.slug])
                    && !category.isEmpty
                    && !taste.triedCategories.contains(category)
            }
            .prefix(sectionLimit)
            .map { item($0, memories: memories, taste: taste, candidates: candidates, hasHistory: true) }
            if !different.isEmpty {
                sections.append(DiscoverySection(id: "different", title: "Farklı bir şey dene", items: Array(different)))
            }
        }

        let quick = ranked.filter { $0.totalMinutes <= 30 }
            .prefix(sectionLimit)
            .map { item($0, memories: memories, taste: taste, candidates: candidates, hasHistory: true) }
        if !quick.isEmpty {
            sections.append(DiscoverySection(id: "quick", title: "Hızlı tarifler", items: Array(quick)))
        }

        let favorites = ranked.filter { candidate in
            let memory = memories[candidate.slug]
            return candidate.rating == .loved || memory?.isFavorite == true || (memory?.timesCooked ?? 0) >= 2
        }
        .prefix(sectionLimit)
        .map { item($0, memories: memories, taste: taste, candidates: candidates, hasHistory: true) }
        if !favorites.isEmpty {
            sections.append(DiscoverySection(id: "favorites", title: "Eski favorilerin", items: Array(favorites)))
        }
        return sections
    }

    private static func item(
        _ candidate: PickerCandidate,
        memories: [String: MealMemorySnapshot],
        taste: TasteProfile,
        candidates: [PickerCandidate],
        hasHistory: Bool
    ) -> DiscoveryItem {
        let reason = RecommendationReasonService.personalReason(
            for: candidate,
            memory: memories[candidate.slug],
            profile: taste,
            catalog: candidates
        ) ?? ""
        return DiscoveryItem(
            slug: candidate.slug,
            reason: reason,
            badge: RecommendationReasonService.badge(for: memories[candidate.slug], hasHistory: hasHistory)
        )
    }

    private static func sharesLovedShape(
        _ candidate: PickerCandidate,
        taste: TasteProfile,
        bySlug: [String: PickerCandidate]
    ) -> Bool {
        for slug in taste.lovedSlugs {
            guard let other = bySlug[slug] else { continue }
            if !candidate.protein.isEmpty, candidate.protein == other.protein { return true }
            let left = candidate.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let right = other.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty, left.caseInsensitiveCompare(right) == .orderedSame { return true }
            if !candidate.tags.isEmpty, !candidate.tags.isDisjoint(with: other.tags) { return true }
        }
        return false
    }
}
