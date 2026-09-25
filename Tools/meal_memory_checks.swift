import Foundation

/// V2 memory, scoring, reset, and discovery checks. Compile with:
///
///   Tools/run_memory_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func candidate(
    _ slug: String,
    score: Int = 60,
    minutes: Int = 40,
    cuisine: String = "TR",
    category: String = "main",
    protein: String = "",
    tags: Set<String> = [],
    ingredients: Set<String> = [],
    rating: MealRating? = nil,
    difficulty: String = "easy"
) -> PickerCandidate {
    PickerCandidate(
        slug: slug,
        totalMinutes: minutes,
        trDogfoodScore: score,
        ingredientIds: ingredients,
        rating: rating,
        cuisine: cuisine,
        category: category,
        tags: tags,
        protein: protein,
        difficulty: difficulty
    )
}

private func prefs(
    minutes: Int = 60,
    discovery: DiscoveryLevel = .balanced,
    repetition: RepeatPreference = .balanced,
    difficulty: DifficultyPreference = .mostlyEasy,
    weekday: WeekdayStyle = .mostlyQuick
) -> PlanningPreferences {
    PlanningPreferences(
        maxCookMinutes: minutes,
        dislikedIngredientIds: [],
        discovery: discovery,
        repetition: repetition,
        difficulty: difficulty,
        weekdayStyle: weekday
    )
}

private func checkConfidenceAndReducer() {
    var once = MealMemorySnapshot(recipeID: "corba")
    MealMemoryReducer.apply(event: .replaced, at: Date(), to: &once)
    check(once.timesReplaced == 1, "one replace increments")
    check(once.confidence == .low, "one replace stays low confidence")
    check(ConfidenceCalculator.scale(6, confidence: .low) < 6, "low confidence shrinks the penalty")

    var loved = MealMemorySnapshot(recipeID: "pilav")
    MealMemoryReducer.apply(event: .loved, at: Date(), to: &loved)
    check(loved.lovedCount == 1 && loved.isFavorite && loved.confidence == .high, "loved is explicit high confidence")

    var cooked = MealMemorySnapshot(recipeID: "kofte")
    let firstCook = Date(timeIntervalSince1970: 1_700_000_000)
    MealMemoryReducer.apply(event: .cooked, at: firstCook, to: &cooked)
    check(cooked.timesCooked == 1 && cooked.lastCookedAt == firstCook, "cook count and date")
    check(cooked.confidence == .low, "one cook is not a settled preference")
    check(cooked.discoveryStatus == .explored, "first cook of an unknown recipe is explored")
    MealMemoryReducer.apply(event: .cooked, at: firstCook.addingTimeInterval(86_400), to: &cooked)
    check(cooked.timesCooked == 2 && cooked.confidence == .medium, "a second cook is medium")

    var never = MealMemorySnapshot(recipeID: "asla")
    MealMemoryReducer.apply(event: .neverAgain, at: Date(), to: &never)
    check(never.neverAgain && never.confidence == .high && !never.isFavorite, "never again is high and clears favorite")

    var noted = MealMemorySnapshot(recipeID: "uzun")
    MealMemoryReducer.apply(event: .okay, at: Date(), reasons: [.tooTimeConsuming, .tooDifficult, .portionSmall], to: &noted)
    check(noted.timeConcernCount == 1 && noted.difficultyConcernCount == 1 && noted.portionConcernCount == 1, "optional reasons land")
    check(noted.okayCount == 1, "okay still records")

    MealMemoryReducer.setFavorite(true, on: &noted)
    check(noted.isFavorite, "favorite flag")
    check(MealMemoryReducer.dataPointCount(in: [once]) == 1, "one event is one data point")
}

private func checkBackfillAndResetShape() {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    let built = MealMemoryBackfill.snapshots(
        feedback: [
            FeedbackSeed(slug: "menemen", rating: .loved, cooked: true, createdAt: when),
        ],
        sightings: [
            RecentMealSighting(slug: "corba", at: when, wasCooked: false),
        ]
    )
    check(built["menemen"]?.timesCooked == 1, "backfill counts the cook")
    check(built["menemen"]?.lovedCount == 1, "backfill keeps the loved rating")
    check(built["corba"]?.lastSelectedAt == when, "backfill remembers a planned sighting")
    check((built["corba"]?.timesCooked ?? 0) == 0, "an uncooked plan is not a cook")

    let cleared = MealMemoryBackfill.snapshots(feedback: [], sightings: [])
    check(cleared.isEmpty, "reset-shaped backfill keeps nothing")
}

private func checkScoring() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let lovedRecipe = candidate("pilav", score: 50, minutes: 40, category: "main", protein: "poultry")
    var lovedMemory = MealMemorySnapshot(recipeID: "pilav")
    MealMemoryReducer.apply(event: .loved, at: now.addingTimeInterval(-20 * 86_400), to: &lovedMemory)
    let lovedScore = PersonalizedScoringService.score(
        lovedRecipe,
        memories: ["pilav": lovedMemory],
        candidates: [lovedRecipe],
        preferences: prefs(),
        anchors: [],
        dayOffset: 0,
        now: now
    )
    check(lovedScore.behavior == 10, "loved behavior is +10, got \(lovedScore.behavior)")

    let plain = candidate("duz", score: 50, minutes: 40, protein: "tofu")
    let plainScore = PersonalizedScoringService.score(
        plain,
        memories: [:],
        candidates: [plain],
        preferences: prefs(),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    check(plainScore.behavior == 0, "no memory has no behavior score")

    var replaced = MealMemorySnapshot(recipeID: "uzun")
    let longRecipe = candidate("uzun", score: 80, minutes: 50)
    for _ in 0..<3 {
        MealMemoryReducer.apply(event: .replaced, at: now.addingTimeInterval(-30 * 86_400), to: &replaced)
    }
    let replacedScore = PersonalizedScoringService.score(
        longRecipe,
        memories: ["uzun": replaced],
        candidates: [longRecipe],
        preferences: prefs(),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    check(replacedScore.behavior <= -6, "three replaces pay the full penalty, got \(replacedScore.behavior)")

    var single = MealMemorySnapshot(recipeID: "tek")
    MealMemoryReducer.apply(event: .replaced, at: now.addingTimeInterval(-30 * 86_400), to: &single)
    let singleScore = PersonalizedScoringService.score(
        candidate("tek", score: 80),
        memories: ["tek": single],
        candidates: [candidate("tek", score: 80)],
        preferences: prefs(),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    check(singleScore.behavior < 0 && singleScore.behavior > -6, "one replace is a soft penalty, got \(singleScore.behavior)")

    let chicken = candidate("tavuk", score: 70, cuisine: "TR", category: "main", protein: "poultry")
    let otherChicken = candidate("sote", score: 55, cuisine: "TR", category: "main", protein: "poultry")
    var loveA = MealMemorySnapshot(recipeID: "tavuk")
    var loveB = MealMemorySnapshot(recipeID: "izgara")
    MealMemoryReducer.apply(event: .loved, at: now.addingTimeInterval(-20 * 86_400), to: &loveA)
    MealMemoryReducer.apply(event: .loved, at: now.addingTimeInterval(-20 * 86_400), to: &loveB)
    let izgara = candidate("izgara", score: 70, cuisine: "TR", category: "main", protein: "poultry")
    let catalog = [chicken, izgara, otherChicken]
    let memories = ["tavuk": loveA, "izgara": loveB]
    let discovery = PersonalizedScoringService.score(
        otherChicken,
        memories: memories,
        candidates: catalog,
        preferences: prefs(discovery: .balanced),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    check(discovery.discovery >= 4, "new recipe in a loved category earns discovery, got \(discovery.discovery)")
    check(discovery.behavior == 4, "similar to a loved recipe is +4, got \(discovery.behavior)")

    let familiar = PersonalizedScoringService.score(
        otherChicken,
        memories: memories,
        candidates: catalog,
        preferences: prefs(discovery: .familiar),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    let adventurous = PersonalizedScoringService.score(
        otherChicken,
        memories: memories,
        candidates: catalog,
        preferences: prefs(discovery: .adventurous),
        anchors: [],
        dayOffset: 6,
        now: now
    )
    check(adventurous.discovery > familiar.discovery, "adventurous outranks familiar on a new recipe")

    var recentLove = lovedMemory
    recentLove.lastCookedAt = now.addingTimeInterval(-4 * 86_400)
    let balancedPenalty = PersonalizedScoringService.score(
        lovedRecipe,
        memories: ["pilav": recentLove],
        candidates: [lovedRecipe],
        preferences: prefs(repetition: .balanced),
        anchors: [],
        dayOffset: 6,
        now: now
    ).repetitionPenalty
    let rarePenalty = PersonalizedScoringService.score(
        lovedRecipe,
        memories: ["pilav": recentLove],
        candidates: [lovedRecipe],
        preferences: prefs(repetition: .occasionally),
        anchors: [],
        dayOffset: 6,
        now: now
    ).repetitionPenalty
    let oftenPenalty = PersonalizedScoringService.score(
        lovedRecipe,
        memories: ["pilav": recentLove],
        candidates: [lovedRecipe],
        preferences: prefs(repetition: .often),
        anchors: [],
        dayOffset: 6,
        now: now
    ).repetitionPenalty
    check(balancedPenalty == 5, "4 days ago is the 3–5 day penalty, got \(balancedPenalty)")
    check(rarePenalty > balancedPenalty && oftenPenalty < balancedPenalty, "repeat preference scales the penalty")

    let neverRecipe = candidate("asla", score: 99, rating: .never)
    let week = PersonalizedScoringService.select(
        candidates: [neverRecipe, candidate("guvenli", score: 40), candidate("guvenli", score: 40)],
        evenings: 2,
        preferences: prefs(),
        memories: ["asla": MealMemorySnapshot(recipeID: "asla", neverAgain: true)],
        now: now
    )
    check(!week.slugs.contains("asla"), "never again stays out of the plan \(week.slugs)")
    check(Set(week.slugs).count == week.slugs.count, "same slug is not repeated in one week")

    let quick = candidate("hizli", score: 40, minutes: 20, cuisine: "GR", protein: "legume")
    let slow = candidate("yavas", score: 90, minutes: 55, cuisine: "JP", protein: "tofu")
    let weekday = PersonalizedScoringService.select(
        candidates: [quick, slow],
        evenings: 1,
        preferences: prefs(weekday: .mostlyQuick),
        memories: [:],
        now: now
    )
    check(weekday.slugs == ["hizli"], "weekday quick style prefers the short meal, got \(weekday.slugs)")

    let hard = candidate("zor", score: 99, cuisine: "MX", difficulty: "hard")
    let easy = candidate("kolay", score: 40, cuisine: "IT", protein: "egg", difficulty: "easy")
    let gated = PersonalizedScoringService.select(
        candidates: [hard, easy],
        evenings: 1,
        preferences: prefs(difficulty: .easyOnly),
        memories: [:],
        now: now
    )
    check(gated.slugs == ["kolay"], "easy-only drops hard recipes, got \(gated.slugs)")
}

private func checkExplanationAndPatterns() {
    let empty = PlanExplanationBuilder.explain(picks: [], hasBehavior: false)
    check(empty == PlanExplanationBuilder.noMemory, "no history uses the plain template")
    check(!empty.contains("sevdiğin"), "plain template does not invent a preference")

    let lovedWeek = PlanExplanationBuilder.explain(
        picks: [
            PlannedPick(slug: "a", minutes: 40, dayOffset: 0, isNew: false, wasLoved: true),
            PlannedPick(slug: "b", minutes: 35, dayOffset: 1, isNew: false, wasLoved: true),
        ],
        hasBehavior: true
    )
    check(lovedWeek == PlanExplanationBuilder.lovedLean, "two loved picks use the loved template")

    let mixed = PlanExplanationBuilder.explain(
        picks: [
            PlannedPick(slug: "a", minutes: 20, dayOffset: 0, isNew: true, wasLoved: false),
            PlannedPick(slug: "b", minutes: 25, dayOffset: 1, isNew: true, wasLoved: false),
            PlannedPick(slug: "c", minutes: 50, dayOffset: 5, isNew: false, wasLoved: false),
        ],
        hasBehavior: true
    )
    check(mixed.contains("2 yeni tarif"), "explanation counts the real new recipes: \(mixed)")
    check(!mixed.lowercased().contains("her zaman"), "explanation stays cautious")

    let tooSoon = MealPatternService.patterns(
        memories: ["a": MealMemorySnapshot(recipeID: "a", timesCooked: 1)],
        candidates: [candidate("a", minutes: 20)]
    )
    check(tooSoon.isEmpty, "one data point hides patterns")

    var quickMemories: [String: MealMemorySnapshot] = [:]
    var quickCandidates: [PickerCandidate] = []
    for slug in ["a", "b", "c"] {
        quickMemories[slug] = MealMemorySnapshot(recipeID: slug, timesCooked: 1)
        quickCandidates.append(candidate(slug, minutes: 20, cuisine: slug.uppercased(), protein: "tofu"))
    }
    let patterns = MealPatternService.patterns(memories: quickMemories, candidates: quickCandidates)
    check(patterns.contains { $0.id == "quick-meals" }, "three quick cooks surface a soft pattern")
    check(patterns.allSatisfy { !$0.message.contains("her zaman") }, "patterns avoid absolute wording")
    let hidden = MealPatternService.patterns(
        memories: quickMemories,
        candidates: quickCandidates,
        dismissed: ["quick-meals"]
    )
    check(!hidden.contains { $0.id == "quick-meals" }, "dismissed pattern stays hidden")
}

private func checkDiscoveryAndReplacement() {
    let never = candidate("asla", score: 99, protein: "tofu", rating: .never)
    let egg = candidate("yumurta", score: 40, minutes: 15, cuisine: "TR", protein: "egg")
    let sections = DiscoverySections.make(
        candidates: [never, egg],
        memories: [:],
        preferences: prefs()
    )
    let slugs = sections.flatMap { section in section.items.map { item in item.slug } }
    check(sections.isEmpty, "no history hides personalized discovery, got \(sections.map(\.title))")
    check(!slugs.contains("asla"), "discovery hides never again")
    check(!sections.contains { $0.id == "recommended" }, "no history hides Sana uygun")
    check(!sections.contains { $0.title.contains("Rutinin") }, "cold start does not claim a routine")

    var cookedEgg = MealMemorySnapshot(recipeID: "yumurta", timesCooked: 1)
    cookedEgg.confidence = .low
    let withHistory = DiscoverySections.make(
        candidates: [never, egg],
        memories: ["yumurta": cookedEgg],
        preferences: prefs()
    )
    check(withHistory.contains { $0.id == "recommended" }, "history shows Sana uygun")
    check(withHistory.first { $0.id == "quick" }?.title == "Hızlı tarifler", "quick section stays factual")
    check(withHistory.allSatisfy { $0.items.count <= DiscoverySections.sectionLimit }, "sections stay capped")
    check(!withHistory.flatMap { $0.items.map(\.slug) }.contains("asla"), "history still hides never again")

    let current = candidate("tavuk", minutes: 50, protein: "poultry", ingredients: ["chicken"])
    let fresh = candidate("yeni", minutes: 30, cuisine: "GR", protein: "legume")
    let known = candidate("eski", minutes: 25, protein: "seafood", rating: .loved)
    let tried = MealReplacement.choices(
        catalog: [current, fresh, known],
        current: current,
        blockedSlugs: ["tavuk"],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.tryNew]
    ).map(\.slug)
    check(tried == ["yeni"], "try-new drops rated recipes, got \(tried)")

    let favorite = MealReplacement.choices(
        catalog: [current, fresh, known],
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.loved]
    ).map(\.slug)
    check(favorite == ["eski"], "favorite chip stays on loved recipes")

    let evening = candidate("aksam", minutes: 50, category: "soup", protein: "legume")
    let fasterMeal = candidate("hizli", minutes: 20, category: "egg", protein: "egg")
    let slowMeal = candidate("yavas", minutes: 70, category: "stew", protein: "tofu")
    let lovedGrill = candidate("tavuk", minutes: 40, category: "grill", protein: "poultry", rating: .loved)
    let similarMeal = candidate("sote", minutes: 35, category: "skillet", protein: "poultry")
    let freshMeal = candidate("yeni", minutes: 30, cuisine: "GR", category: "salad", protein: "dairy")
    let banned = candidate("asla", score: 99, minutes: 15, category: "ban", protein: "tofu", rating: .never)
    var hiddenMemory = MealMemorySnapshot(recipeID: "gizli")
    hiddenMemory.neverAgain = true
    let hidden = candidate("gizli", minutes: 15, category: "hide", protein: "egg")
    let safe = candidate("guvenli", minutes: 20, category: "safe", protein: "dairy")
    let intentCatalog = [evening, fasterMeal, slowMeal, lovedGrill, similarMeal, known, freshMeal, banned, hidden, safe]
    let context = ReplacementMemory(
        memories: ["gizli": hiddenMemory],
        preferences: prefs(),
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let faster = MealReplacement.choices(
        catalog: intentCatalog,
        current: evening,
        blockedSlugs: [evening.slug],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.faster],
        memory: context
    ).map(\.slug)
    check(faster.contains("hizli") && !faster.contains("yavas"), "faster keeps the shorter meal, got \(faster)")
    check(!faster.contains("asla") && !faster.contains("gizli"), "faster still drops never again, got \(faster)")
    let similarSlugs = MealReplacement.choices(
        catalog: intentCatalog,
        current: evening,
        blockedSlugs: [evening.slug],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.similarLoved],
        memory: context
    ).map(\.slug)
    check(similarSlugs == ["sote"], "similar-to-loved follows the loved protein, got \(similarSlugs)")
}

private func checkPresentation() {
    let cooked = MealMemorySnapshot(recipeID: "pilav", timesCooked: 2)
    check(RecommendationReasonService.badge(for: cooked, hasHistory: false) == nil, "no history hides the familiar badge")
    check(RecommendationReasonService.badge(for: nil, hasHistory: false) == nil, "no history hides the new badge")
    check(RecommendationReasonService.badge(for: cooked, hasHistory: true) == .familiar, "cooked history is Tanıdık")
    check(RecommendationReasonService.badge(for: nil, hasHistory: true) == .new, "unseen recipe with history is Yeni")

    check(
        SkipControl.appearance(isSkipped: false, isCooked: false, isWorking: false) == .idle,
        "idle skip stays tappable"
    )
    check(
        SkipControl.appearance(isSkipped: true, isCooked: false, isWorking: false) == .selected,
        "skipped meal uses the selected treatment"
    )
    check(SkipControl.usesFilledAccent(.selected) && !SkipControl.usesFilledAccent(.idle), "only the skipped control is filled")
    check(SkipControl.showsAffordance(isCooked: false), "an uncooked meal still offers skip")
    check(!SkipControl.showsAffordance(isCooked: true), "a cooked meal hides skip")
    check(
        SkipControl.recordsAsSkipped(skippedAt: Date(timeIntervalSince1970: 1_700_000_000), cookedAt: nil),
        "a skip stays visible until the meal is cooked"
    )
    check(
        !SkipControl.recordsAsSkipped(
            skippedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cookedAt: Date(timeIntervalSince1970: 1_700_003_600)
        ),
        "cooking clears the skipped state"
    )

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let thisWeek = WeekCalendar.weekStart(containing: now)
    let mealID = UUID()
    check(
        CookBarGate.showsCookBar(allowsCookBar: true, plannedMealID: mealID, mealWeekStart: thisWeek, now: now),
        "this week's planned meal can show the cook bar"
    )
    check(
        !CookBarGate.showsCookBar(allowsCookBar: false, plannedMealID: mealID, mealWeekStart: thisWeek, now: now),
        "Tarifler does not show the cook bar"
    )
    check(
        !CookBarGate.showsCookBar(
            allowsCookBar: true,
            plannedMealID: mealID,
            mealWeekStart: WeekCalendar.date(weekStart: thisWeek, dayOffset: -7),
            now: now
        ),
        "last week's meal does not show the cook bar"
    )
}

@main
struct MealMemoryChecks {
    static func main() {
        checkConfidenceAndReducer()
        checkBackfillAndResetShape()
        checkScoring()
        checkExplanationAndPatterns()
        checkDiscoveryAndReplacement()
        checkPresentation()
        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("meal memory checks passed")
    }
}
