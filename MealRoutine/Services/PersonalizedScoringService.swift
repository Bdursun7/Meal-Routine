import Foundation

/// Behavior-based ranker used by the weekly plan and smart replacement.
///
/// `MealRecommender.pick` stays the V1 path for the existing checks.
/// This service is what week generation calls. Never-again and disliked
/// ingredients stay hard filters at every discovery level.
enum PersonalizedScoringService {
    static func profile(
        memories: [String: MealMemorySnapshot],
        candidates: [PickerCandidate]
    ) -> TasteProfile {
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var categoryLoves: [String: Int] = [:]
        var proteinLoves: [String: Int] = [:]
        var cuisineLoves: [String: Int] = [:]
        var cuisineCooks: [String: Int] = [:]
        var tried: Set<String> = []
        var lovedSlugs: Set<String> = []
        var cookMinutes: [Int] = []

        for (slug, memory) in memories {
            guard let candidate = bySlug[slug] else { continue }
            let category = normalized(candidate.category)
            let cuisine = normalizedCuisine(candidate.cuisine)
            if memory.timesCooked > 0 || memory.lovedCount > 0 || memory.okayCount > 0 {
                if !category.isEmpty { tried.insert(category) }
            }
            let stillLoved = memory.lovedCount > 0
                && memory.latestRating != .okay
                && memory.latestRating != .never
            if stillLoved {
                lovedSlugs.insert(slug)
                if !category.isEmpty { categoryLoves[category, default: 0] += 1 }
                if !candidate.protein.isEmpty { proteinLoves[candidate.protein, default: 0] += 1 }
                if !cuisine.isEmpty { cuisineLoves[cuisine, default: 0] += 1 }
            }
            if memory.timesCooked > 0, !cuisine.isEmpty {
                cuisineCooks[cuisine, default: 0] += memory.timesCooked
            }
            if memory.timesCooked > 0 {
                for _ in 0..<min(memory.timesCooked, 8) {
                    cookMinutes.append(candidate.totalMinutes)
                }
            }
        }

        let establishedCategories = Set(categoryLoves.filter { $0.value >= 2 }.map(\.key))
        let establishedProteins = Set(proteinLoves.filter { $0.value >= 2 }.map(\.key))
        let establishedCuisines = Set(cuisineLoves.filter { $0.value >= 2 }.map(\.key))
        let frequent = Set(cuisineCooks.filter { $0.value >= 3 }.map(\.key)).union(establishedCuisines)

        return TasteProfile(
            lovedCategories: establishedCategories,
            lovedProteins: establishedProteins,
            lovedCuisines: establishedCuisines,
            frequentCuisines: frequent,
            triedCategories: tried,
            lovedSlugs: lovedSlugs,
            dataPointCount: MealMemoryReducer.dataPointCount(in: Array(memories.values)),
            usualCookMinutes: medianMinutes(cookMinutes)
        )
    }

    static func select(
        candidates: [PickerCandidate],
        evenings: Int,
        preferences: PlanningPreferences,
        memories: [String: MealMemorySnapshot],
        blockedSlugs: Set<String> = [],
        initialAnchors: [PickerCandidate] = [],
        startDayOffset: Int = 0,
        now: Date = .now
    ) -> (slugs: [String], explanation: String, scores: [String: RecipeMemoryScore]) {
        let limit = min(max(evenings, 0), MealRecommender.eveningCap)
        guard limit > 0 else { return ([], PlanExplanationBuilder.noMemory, [:]) }

        let taste = profile(memories: memories, candidates: candidates)
        let strict = pool(
            candidates: candidates,
            preferences: preferences,
            memories: memories,
            blockedSlugs: blockedSlugs,
            relaxLovedGap: false,
            relaxDifficulty: false,
            now: now
        )
        let picked = fill(
            pool: strict,
            limit: limit,
            preferences: preferences,
            memories: memories,
            taste: taste,
            candidates: candidates,
            initialAnchors: initialAnchors,
            startDayOffset: startDayOffset,
            now: now
        )
        let chosen = picked.chosen.count < limit
            ? fill(
                pool: pool(
                    candidates: candidates,
                    preferences: preferences,
                    memories: memories,
                    blockedSlugs: blockedSlugs,
                    relaxLovedGap: true,
                    relaxDifficulty: true,
                    now: now
                ),
                limit: limit,
                preferences: preferences,
                memories: memories,
                taste: taste,
                candidates: candidates,
                initialAnchors: initialAnchors,
                startDayOffset: startDayOffset,
                now: now
            )
            : picked

        let picks = chosen.chosen.enumerated().map { index, candidate in
            let memory = memories[candidate.slug]
            return PlannedPick(
                slug: candidate.slug,
                minutes: candidate.totalMinutes,
                dayOffset: startDayOffset + index,
                isNew: RecommendationReasonService.isNew(memory),
                wasLoved: (memory?.lovedCount ?? 0) > 0
            )
        }
        let explanation = PlanExplanationBuilder.explain(
            picks: picks,
            hasBehavior: taste.dataPointCount > 0
        )
        return (chosen.chosen.map(\.slug), explanation, chosen.scores)
    }

    static func score(
        _ candidate: PickerCandidate,
        memories: [String: MealMemorySnapshot],
        candidates: [PickerCandidate],
        preferences: PlanningPreferences,
        anchors: [PickerCandidate],
        dayOffset: Int,
        now: Date
    ) -> RecipeMemoryScore {
        let taste = profile(memories: memories, candidates: candidates)
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        return score(
            candidate,
            memory: memories[candidate.slug],
            taste: taste,
            catalogBySlug: bySlug,
            preferences: preferences,
            anchors: anchors,
            dayOffset: dayOffset,
            now: now
        )
    }

    /// One rank for a list row. The taste profile and slug index are built by the caller
    /// once for the whole catalog, not once per comparison.
    static func listRank(
        _ candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        taste: TasteProfile,
        catalogBySlug: [String: PickerCandidate],
        preferences: PlanningPreferences,
        now: Date
    ) -> Int {
        score(
            candidate,
            memory: memory,
            taste: taste,
            catalogBySlug: catalogBySlug,
            preferences: preferences,
            anchors: [],
            dayOffset: 0,
            now: now
        ).final
    }

    static func isEligible(
        _ candidate: PickerCandidate,
        preferences: PlanningPreferences,
        memory: MealMemorySnapshot?,
        blockedSlugs: Set<String>,
        enforceLovedGap: Bool = false,
        enforceDifficulty: Bool = true,
        now: Date = .now
    ) -> Bool {
        if blockedSlugs.contains(candidate.slug) { return false }
        if candidate.rating == .never || memory?.neverAgain == true { return false }
        if candidate.totalMinutes > preferences.maxCookMinutes { return false }
        if !candidate.ingredientIds.isDisjoint(with: preferences.dislikedIngredientIds) { return false }
        if enforceDifficulty, !allowsDifficulty(candidate.difficulty, preference: preferences.difficulty) {
            return false
        }
        if enforceLovedGap, let memory, isInsideLovedGap(memory, preference: preferences.repetition, now: now) {
            return false
        }
        return true
    }

    static func dayAge(from date: Date, to now: Date) -> Int {
        let seconds = now.timeIntervalSince(date)
        if seconds <= 0 { return 0 }
        return Int(seconds / Double(MealRecommender.secondsPerDay))
    }

    private static func fill(
        pool: [PickerCandidate],
        limit: Int,
        preferences: PlanningPreferences,
        memories: [String: MealMemorySnapshot],
        taste: TasteProfile,
        candidates: [PickerCandidate],
        initialAnchors: [PickerCandidate],
        startDayOffset: Int,
        now: Date
    ) -> (chosen: [PickerCandidate], scores: [String: RecipeMemoryScore]) {
        var remaining = pool
        var anchors = initialAnchors
        var chosen: [PickerCandidate] = []
        var scores: [String: RecipeMemoryScore] = [:]
        var offset = startDayOffset
        let bySlug = Dictionary(candidates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        while chosen.count < limit {
            let ranked = remaining.map { candidate in
                (
                    candidate,
                    score(
                        candidate,
                        memory: memories[candidate.slug],
                        taste: taste,
                        catalogBySlug: bySlug,
                        preferences: preferences,
                        anchors: anchors,
                        dayOffset: offset,
                        now: now
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.1.final != rhs.1.final { return lhs.1.final > rhs.1.final }
                return lhs.0.slug < rhs.0.slug
            }
            guard let next = ranked.first else { break }
            chosen.append(next.0)
            scores[next.0.slug] = next.1
            anchors.append(next.0)
            remaining.removeAll { $0.slug == next.0.slug }
            offset += 1
        }
        return (chosen, scores)
    }

    private static func pool(
        candidates: [PickerCandidate],
        preferences: PlanningPreferences,
        memories: [String: MealMemorySnapshot],
        blockedSlugs: Set<String>,
        relaxLovedGap: Bool,
        relaxDifficulty: Bool,
        now: Date
    ) -> [PickerCandidate] {
        candidates.filter { candidate in
            isEligible(
                candidate,
                preferences: preferences,
                memory: memories[candidate.slug],
                blockedSlugs: blockedSlugs,
                enforceLovedGap: !relaxLovedGap,
                enforceDifficulty: !relaxDifficulty,
                now: now
            )
        }
    }

    private static func score(
        _ candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        taste: TasteProfile,
        catalogBySlug: [String: PickerCandidate],
        preferences: PlanningPreferences,
        anchors: [PickerCandidate],
        dayOffset: Int,
        now: Date
    ) -> RecipeMemoryScore {
        var preference = candidate.trDogfoodScore / 10
        let category = normalized(candidate.category)
        let cuisine = normalizedCuisine(candidate.cuisine)
        if taste.lovedCategories.contains(category) { preference += 5 }
        if !candidate.protein.isEmpty, taste.lovedProteins.contains(candidate.protein) { preference += 5 }
        if taste.frequentCuisines.contains(cuisine) { preference += 3 }
        if candidate.totalMinutes <= comfortableMinutes(preferences.maxCookMinutes) { preference += 2 }
        preference += weekdayBias(candidate, dayOffset: dayOffset, style: preferences.weekdayStyle, anchors: anchors)
        preference += difficultyBias(candidate.difficulty, preference: preferences.difficulty)

        let behavior = behaviorScore(candidate, memory: memory, taste: taste, catalogBySlug: catalogBySlug)
        let repetition = repetitionPenalty(memory: memory, preference: preferences.repetition, now: now)
        let discovery = discoveryScore(
            candidate,
            memory: memory,
            taste: taste,
            level: preferences.discovery
        )
        let variety = varietyScore(candidate, anchors: anchors, style: preferences.weekdayStyle, dayOffset: dayOffset)
        return RecipeMemoryScore(
            preference: preference,
            behavior: behavior,
            variety: variety,
            repetitionPenalty: repetition,
            discovery: discovery
        )
    }

    private static func behaviorScore(
        _ candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        taste: TasteProfile,
        catalogBySlug: [String: PickerCandidate]
    ) -> Int {
        guard let memory else {
            return similarBonus(candidate, taste: taste, catalogBySlug: catalogBySlug)
        }
        var score = 0
        if memory.latestRating == .loved || (memory.latestRating == nil && memory.lovedCount > 0) {
            score += 10
        } else if memory.latestRating == .okay || (memory.latestRating == nil && memory.okayCount > 0) {
            score += 2
        }
        if memory.timesCooked >= 2 {
            score += ConfidenceCalculator.scale(
                6,
                confidence: ConfidenceCalculator.cookRepeatConfidence(timesCooked: memory.timesCooked)
            )
        }
        if memory.wouldMakeAgainCount > 0 {
            score += 3
        }
        if memory.isFavorite, memory.lovedCount == 0 {
            score += 4
        }
        if memory.timesReplaced > 0 {
            score -= ConfidenceCalculator.scale(
                6,
                confidence: ConfidenceCalculator.replacementConfidence(timesReplaced: memory.timesReplaced)
            )
        }
        if memory.timesSkipped >= 2 {
            let confidence: ConfidenceLevel = memory.timesSkipped >= 3 ? .medium : .low
            score -= ConfidenceCalculator.scale(4, confidence: confidence)
        }
        if memory.timeConcernCount > 0 {
            let confidence: ConfidenceLevel = memory.timeConcernCount >= 2 ? .medium : .low
            score -= ConfidenceCalculator.scale(7, confidence: confidence)
        }
        if memory.difficultyConcernCount > 0 {
            let confidence: ConfidenceLevel = memory.difficultyConcernCount >= 2 ? .medium : .low
            score -= ConfidenceCalculator.scale(6, confidence: confidence)
        }
        if memory.neverAgain {
            score -= 100
        }
        if memory.lovedCount == 0 {
            score += similarBonus(candidate, taste: taste, catalogBySlug: catalogBySlug)
        }
        return score
    }

    private static func similarBonus(
        _ candidate: PickerCandidate,
        taste: TasteProfile,
        catalogBySlug: [String: PickerCandidate]
    ) -> Int {
        for slug in taste.lovedSlugs where slug != candidate.slug {
            guard let other = catalogBySlug[slug] else { continue }
            if !candidate.protein.isEmpty, candidate.protein == other.protein { return 4 }
            if same(candidate.category, other.category) { return 4 }
            if !candidate.tags.isEmpty, !candidate.tags.isDisjoint(with: other.tags) { return 4 }
        }
        return 0
    }

    private static func repetitionPenalty(
        memory: MealMemorySnapshot?,
        preference: RepeatPreference,
        now: Date
    ) -> Int {
        guard let memory else { return 0 }
        guard let last = memory.lastCookedAt ?? memory.lastSelectedAt else { return 0 }
        let days = dayAge(from: last, to: now)
        var base = 0
        if days <= 2 {
            base = 10
        } else if days <= 5 {
            base = 5
        } else if days <= 10 {
            base = 2
        }
        if memory.timesCooked >= 4, days <= 14 {
            base = max(base, 2)
        }
        switch preference {
        case .occasionally:
            return base * 2
        case .balanced:
            return base
        case .often:
            return base / 2
        }
    }

    private static func discoveryScore(
        _ candidate: PickerCandidate,
        memory: MealMemorySnapshot?,
        taste: TasteProfile,
        level: DiscoveryLevel
    ) -> Int {
        let isNew = RecommendationReasonService.isNew(memory)
        var score = 0
        if isNew {
            if taste.lovedCategories.contains(normalized(candidate.category)) { score += 4 }
            if !candidate.protein.isEmpty, taste.lovedProteins.contains(candidate.protein) { score += 3 }
            if taste.lovedCuisines.contains(normalizedCuisine(candidate.cuisine)) { score += 3 }
            if !normalized(candidate.category).isEmpty,
               !taste.triedCategories.contains(normalized(candidate.category)) {
                score += 1
            }
        }
        switch level {
        case .familiar:
            score /= 4
            if !isNew { score += 6 }
            else { score -= 2 }
        case .balanced:
            if !isNew { score += 1 }
        case .adventurous:
            score *= 2
            if isNew { score += 2 }
        }
        return score
    }

    private static func varietyScore(
        _ candidate: PickerCandidate,
        anchors: [PickerCandidate],
        style: WeekdayStyle,
        dayOffset: Int
    ) -> Int {
        var score = 0
        for anchor in anchors {
            if same(candidate.cuisine, anchor.cuisine) {
                score -= 3
            } else if !candidate.cuisine.isEmpty, !anchor.cuisine.isEmpty {
                score += 1
            }
            if !candidate.protein.isEmpty, candidate.protein == anchor.protein {
                score -= 3
            } else if !candidate.protein.isEmpty, !anchor.protein.isEmpty {
                score += 1
            }
            if same(candidate.category, anchor.category) {
                score -= 2
            }
        }
        if dayOffset < 5, style == .moreVariety, !anchors.isEmpty {
            let cuisines = Set(anchors.map { normalizedCuisine($0.cuisine) })
            if !cuisines.contains(normalizedCuisine(candidate.cuisine)) {
                score += 2
            }
        }
        return max(score, -12)
    }

    private static func weekdayBias(
        _ candidate: PickerCandidate,
        dayOffset: Int,
        style: WeekdayStyle,
        anchors: [PickerCandidate]
    ) -> Int {
        guard dayOffset < 5 else { return 0 }
        switch style {
        case .mostlyQuick:
            if candidate.totalMinutes <= 30 { return 4 }
            if candidate.totalMinutes <= 45 { return 2 }
            return -3
        case .balanced:
            return candidate.totalMinutes <= 45 ? 1 : 0
        case .moreVariety:
            _ = anchors
            return 0
        }
    }

    private static func difficultyBias(_ raw: String, preference: DifficultyPreference) -> Int {
        let difficulty = normalized(raw)
        if difficulty == "medium", preference == .mostlyEasy { return -4 }
        if difficulty == "hard" { return -8 }
        return 0
    }

    private static func allowsDifficulty(_ raw: String, preference: DifficultyPreference) -> Bool {
        let difficulty = normalized(raw)
        if difficulty.isEmpty || difficulty == "easy" { return true }
        switch preference {
        case .easyOnly:
            return false
        case .mostlyEasy, .openToMedium:
            return difficulty != "hard"
        }
    }

    private static func isInsideLovedGap(
        _ memory: MealMemorySnapshot,
        preference: RepeatPreference,
        now: Date
    ) -> Bool {
        guard memory.lovedCount > 0 || memory.isFavorite else { return false }
        guard let last = memory.lastCookedAt ?? memory.lastSelectedAt else { return false }
        var gap = preference.lovedGapDays
        if memory.timesCooked >= 4, preference != .often {
            gap += 3
        }
        return dayAge(from: last, to: now) < gap
    }

    private static func comfortableMinutes(_ maxCookMinutes: Int) -> Int {
        max(20, maxCookMinutes - 15)
    }

    private static func medianMinutes(_ values: [Int]) -> Int? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedCuisine(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }
}
