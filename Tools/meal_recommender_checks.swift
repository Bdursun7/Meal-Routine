import Foundation

/// Focused checks for the deterministic recommender. Compile with the Foundation-only
/// sources (no SwiftData, no Xcode):
///
///   Tools/run_recommender_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func candidate(
    _ slug: String,
    score: Int,
    minutes: Int = 40,
    cuisine: String,
    category: String = "main",
    protein: String = "",
    tags: Set<String> = [],
    ingredients: Set<String> = [],
    rating: MealRating? = nil
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
        protein: protein
    )
}

private func sampleCatalog() -> [PickerCandidate] {
    [
        candidate("menemen", score: 91, minutes: 30, cuisine: "TR", category: "breakfast", protein: "egg", ingredients: ["eggs"]),
        candidate("mercimek", score: 89, minutes: 45, cuisine: "TR", category: "soup", protein: "legume"),
        candidate("iskender", score: 85, minutes: 60, cuisine: "TR", category: "main", protein: "red-meat"),
        candidate("lahmacun", score: 77, minutes: 80, cuisine: "TR", category: "main", protein: "red-meat"),
        candidate("souvlaki", score: 71, minutes: 35, cuisine: "GR", category: "main", protein: "red-meat"),
        candidate("chapli", score: 68, minutes: 45, cuisine: "PK", category: "main", protein: "red-meat"),
        candidate("dal", score: 68, minutes: 45, cuisine: "IN", category: "main", protein: "legume"),
        candidate("tarator", score: 61, minutes: 20, cuisine: "BG", category: "soup", protein: "dairy"),
    ]
}

private func checkFilters() {
    let catalog = sampleCatalog()
    let never = MealRecommender.pick(
        candidates: catalog,
        evenings: 1,
        maxCookMinutes: 90,
        dislikedIngredientIds: [],
        excludingSlugs: [],
        recent: [],
        anchoredMeals: []
    )
    // Baseline without the never rating is menemen. A never rating must remove it.
    check(never == ["menemen"], "baseline first pick was \(never)")

    var blocked = catalog
    blocked[0].rating = .never
    let withoutNever = MealRecommender.pick(
        candidates: blocked,
        evenings: 1,
        maxCookMinutes: 90,
        dislikedIngredientIds: []
    )
    check(withoutNever == ["mercimek"], "never-again should hard-exclude, got \(withoutNever)")

    let disliked = MealRecommender.pick(
        candidates: catalog,
        evenings: 1,
        maxCookMinutes: 90,
        dislikedIngredientIds: ["eggs"]
    )
    check(disliked == ["mercimek"], "disliked ingredient should hard-exclude, got \(disliked)")

    let quick = MealRecommender.pick(
        candidates: catalog,
        evenings: 5,
        maxCookMinutes: 30,
        dislikedIngredientIds: []
    )
    check(quick == ["menemen", "tarator"], "30 minute cap should keep only menemen and tarator, got \(quick)")

    let capped = MealRecommender.pick(
        candidates: catalog,
        evenings: 8,
        maxCookMinutes: 90,
        dislikedIngredientIds: []
    )
    check(capped.count == MealRecommender.eveningCap, "evenings should cap at 5, got \(capped.count)")
    check(MealRecommender.pick(candidates: catalog, evenings: 0, maxCookMinutes: 90, dislikedIngredientIds: []).isEmpty, "zero evenings")
}

private func checkLovedAndRecency() {
    let fresh = [
        candidate("loved-low", score: 40, cuisine: "JP", protein: "tofu", rating: .loved),
        candidate("plain-high", score: 90, cuisine: "MX", protein: "poultry"),
    ]
    let lovedWins = MealRecommender.pick(candidates: fresh, evenings: 1, maxCookMinutes: 60, dislikedIngredientIds: [])
    check(lovedWins == ["loved-low"], "loved boost should beat a curation gap smaller than the boost, got \(lovedWins)")

    let wider = [
        candidate("loved-low", score: 40, cuisine: "JP", protein: "tofu", rating: .loved),
        candidate("plain-higher", score: 40 + MealRecommender.lovedBoost + 5, cuisine: "MX", protein: "poultry"),
    ]
    let lovedLoses = MealRecommender.pick(candidates: wider, evenings: 1, maxCookMinutes: 60, dislikedIngredientIds: [])
    check(lovedLoses == ["plain-higher"], "loved boost is finite, got \(lovedLoses)")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let catalog = sampleCatalog()
    let cooked = [
        RecentMealSighting(slug: "menemen", at: now, wasCooked: true)
    ]
    let afterCook = MealRecommender.pick(
        candidates: catalog,
        evenings: 1,
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        recent: cooked,
        now: now
    )
    check(afterCook == ["mercimek"], "a meal cooked today should yield to the next fresh score, got \(afterCook)")

    var lovedCatalog = catalog
    lovedCatalog[0].rating = .loved
    let lovedCooked = MealRecommender.pick(
        candidates: lovedCatalog,
        evenings: 1,
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        recent: cooked,
        now: now
    )
    check(lovedCooked == ["mercimek"], "loved + cooked today should still yield, got \(lovedCooked)")

    let lovedFresh = MealRecommender.pick(
        candidates: lovedCatalog,
        evenings: 1,
        maxCookMinutes: 60,
        dislikedIngredientIds: []
    )
    check(lovedFresh == ["menemen"], "loved and not recent should stay on top, got \(lovedFresh)")

    let planned = [RecentMealSighting(slug: "menemen", at: now, wasCooked: false)]
    let cookedPenalty = MealRecommender.recencyPenalty(for: "menemen", recent: cooked, now: now)
    let plannedPenalty = MealRecommender.recencyPenalty(for: "menemen", recent: planned, now: now)
    check(cookedPenalty == MealRecommender.cookedPenaltyCap, "cooked today penalty \(cookedPenalty)")
    check(plannedPenalty == MealRecommender.plannedPenaltyCap, "planned today penalty \(plannedPenalty)")
    check(cookedPenalty > plannedPenalty, "cooked should outrank planned as a penalty")

    let both = cooked + planned
    check(
        MealRecommender.recencyPenalty(for: "menemen", recent: both, now: now) == cookedPenalty,
        "the stronger sighting should win"
    )

    let stale = now.addingTimeInterval(-Double(MealRecommender.recencyWindowDays * MealRecommender.secondsPerDay))
    check(
        MealRecommender.recencyPenalty(
            for: "menemen",
            recent: [RecentMealSighting(slug: "menemen", at: stale, wasCooked: true)],
            now: now
        ) == 0,
        "a sighting at the window edge should not penalize"
    )
    let outside = stale.addingTimeInterval(-60)
    check(
        MealRecommender.recencyPenalty(
            for: "menemen",
            recent: [RecentMealSighting(slug: "menemen", at: outside, wasCooked: true)],
            now: now
        ) == 0,
        "older than the window should not penalize"
    )
    check(
        MealRecommender.recencyPenalty(for: "other", recent: cooked, now: now) == 0,
        "a different slug should not inherit the penalty"
    )
}

private func checkDiversitySignals() {
    let left = candidate("a", score: 10, cuisine: "TR", category: "main", protein: "poultry", tags: ["kebab", "grill"])
    let sameCountry = candidate("b", score: 10, cuisine: "tr", category: "soup", protein: "egg", tags: ["stew"])
    let sameRegion = candidate("c", score: 10, cuisine: "GR", category: "salad", protein: "seafood", tags: [])
    let far = candidate("d", score: 10, cuisine: "JP", category: "main", protein: "poultry", tags: ["kebab"])

    check(
        MealRecommender.diversityPenalty(for: sameCountry, anchoredMeals: [left]) == MealRecommender.sameCuisinePenalty,
        "same cuisine should not also add the region penalty"
    )
    check(
        MealRecommender.diversityPenalty(for: sameRegion, anchoredMeals: [left]) == MealRecommender.similarCuisinePenalty,
        "TR and GR should share a region penalty only"
    )
    let farPenalty = MealRecommender.diversityPenalty(for: far, anchoredMeals: [left])
    let expectedFar = MealRecommender.sameCategoryPenalty
        + MealRecommender.sameProteinPenalty
        + MealRecommender.sharedTagPenalty
    check(farPenalty == expectedFar, "category + protein + one shared tag, got \(farPenalty)")

    check(
        MealRecommender.diversityPenalty(
            for: candidate("e", score: 1, cuisine: "JP", category: "", protein: ""),
            anchoredMeals: [candidate("f", score: 1, cuisine: "MX", category: "", protein: "")]
        ) == 0,
        "empty protein is not a repeat, and JP/MX are not the same region"
    )

    let identical = MealRecommender.sameCuisinePenalty
        + MealRecommender.sameCategoryPenalty
        + MealRecommender.sameProteinPenalty
        + MealRecommender.sharedTagPenalty * 2
    let stacked = MealRecommender.diversityPenalty(for: left, anchoredMeals: [left, far, sameCountry])
    let uncapped = identical + expectedFar + MealRecommender.sameCuisinePenalty
    check(
        stacked == min(uncapped, MealRecommender.diversityPenaltyCap),
        "stacked diversity \(stacked), expected \(min(uncapped, MealRecommender.diversityPenaltyCap))"
    )
    let capped = MealRecommender.diversityPenalty(for: left, anchoredMeals: [left, left])
    check(capped == MealRecommender.diversityPenaltyCap, "diversity penalty should cap, got \(capped)")
}

private func checkWeekAndReplace() {
    let catalog = sampleCatalog()
    let week = MealRecommender.pick(
        candidates: catalog,
        evenings: 5,
        maxCookMinutes: 60,
        dislikedIngredientIds: []
    )
    let again = MealRecommender.pick(
        candidates: catalog,
        evenings: 5,
        maxCookMinutes: 60,
        dislikedIngredientIds: []
    )
    check(week == again, "week fill should be deterministic")
    check(
        week == ["menemen", "mercimek", "chapli", "tarator", "dal"],
        "sample week should spread cuisine and protein, got \(week)"
    )
    check(!week.contains("lahmacun"), "over the time cap")
    check(Set(week).count == week.count, "no repeated slugs")

    let bySlug = Dictionary(uniqueKeysWithValues: catalog.map { ($0.slug, $0) })
    guard let lastSlug = week.last, let lastMeal = bySlug[lastSlug] else {
        check(false, "sample week was empty")
        return
    }
    let anchors = week.dropLast().compactMap { bySlug[$0] }
    let replacement = MealRecommender.pick(
        candidates: catalog,
        evenings: 1,
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        excludingSlugs: Set(week),
        anchoredMeals: anchors + [lastMeal]
    )
    check(replacement == ["souvlaki"], "replacing the last evening should leave the week, got \(replacement)")

    // Değiştir the Turkish lamb main while the rest of a mixed week stays put.
    let iskender = bySlug["iskender"]!
    let held = ["menemen", "souvlaki", "tarator", "dal"].compactMap { bySlug[$0] }
    let swapped = MealRecommender.pick(
        candidates: catalog,
        evenings: 1,
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        excludingSlugs: Set(held.map(\.slug) + [iskender.slug]),
        anchoredMeals: held + [iskender]
    )
    check(swapped == ["mercimek"], "replace should leave Turkish red meat for a different protein, got \(swapped)")
}

private func checkProteinAndRegion() {
    check(MealRecommender.proteinFamily(in: ["salt", "chicken", "eggs"]) == "poultry", "first mapped protein wins")
    check(MealRecommender.proteinFamily(in: ["eggs", "chicken"]) == "egg", "egg listed first")
    check(MealRecommender.proteinFamily(in: ["greenbeans", "fishsauce", "soy"]) == "", "condiments and vegetables are not protein")
    check(MealRecommender.proteinFamily(in: ["butterbeans"]) == "legume", "butterbeans")
    check(MealRecommender.proteinFamily(in: ["yogurt"]) == "dairy", "yogurt")
    check(MealRecommender.cuisineRegion(for: "tr") == "mediterranean", "TR region")
    check(MealRecommender.cuisineRegion(for: "GR") == "mediterranean", "GR region")
    check(MealRecommender.cuisineRegion(for: "JP") == "east-asia", "JP region")
    check(MealRecommender.cuisineRegion(for: "ZZ") == "", "unknown country has no region")
}

private func checkExposureLog() {
    let suite = "MealRecommenderChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let cooked = RecentMealSighting(slug: "menemen", at: now, wasCooked: true)
    let planned = RecentMealSighting(slug: "menemen", at: now.addingTimeInterval(-3_600), wasCooked: false)
    let stale = RecentMealSighting(
        slug: "dal",
        at: now.addingTimeInterval(-Double((MealRecommender.recencyWindowDays + 2) * MealRecommender.secondsPerDay)),
        wasCooked: true
    )
    let roundTrip = MealExposureLog.decode([MealExposureLog.encode(cooked)])
    check(roundTrip == [cooked], "encode/decode round trip, got \(roundTrip)")
    check(MealExposureLog.decode(["bad", "only\tone"]).isEmpty, "malformed lines should be ignored")

    let merged = MealExposureLog.merge(existing: [planned, stale], additions: [cooked], now: now)
    check(merged == [cooked], "merge should keep the stronger in-window sighting, got \(merged)")

    MealExposureLog.record([cooked, planned, stale], now: now, defaults: defaults)
    let loaded = MealExposureLog.load(from: defaults)
    check(loaded == [cooked], "defaults log should persist the merged sighting, got \(loaded)")
    defaults.removePersistentDomain(forName: suite)
}

private func checkBundledCatalog() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("MealRoutine/Recipes/recipes.v1.json")
    let data = try Data(contentsOf: url)
    let file = try JSONDecoder().decode(RecipeCatalogFile.self, from: data)
    check(file.recipes.count == 125, "catalog count \(file.recipes.count)")
    let candidates = file.recipes.map { dto -> PickerCandidate in
        let ids = dto.ingredients.map(\.id)
        let course = dto.unitoolsCategory.isEmpty ? dto.category : dto.unitoolsCategory
        return PickerCandidate(
            slug: dto.id,
            totalMinutes: dto.totalMinutes,
            trDogfoodScore: dto.trDogfoodScore,
            ingredientIds: Set(ids),
            rating: nil,
            cuisine: dto.country,
            category: course,
            tags: Set(dto.tags.map { $0.lowercased() }),
            protein: MealRecommender.proteinFamily(in: ids)
        )
    }
    let bySlug = Dictionary(uniqueKeysWithValues: candidates.map { ($0.slug, $0) })
    let week = MealRecommender.pick(
        candidates: candidates,
        evenings: 5,
        maxCookMinutes: 60,
        dislikedIngredientIds: []
    )
    let repeatWeek = MealRecommender.pick(
        candidates: candidates,
        evenings: 5,
        maxCookMinutes: 60,
        dislikedIngredientIds: []
    )
    check(week == repeatWeek, "bundled catalog fill should be deterministic")
    check(week.count == 5, "bundled week count \(week)")
    let picked = week.compactMap { bySlug[$0] }
    check(picked.allSatisfy { $0.totalMinutes <= 60 }, "bundled week respects the time cap")
    let cuisines = Set(picked.map { $0.cuisine.uppercased() })
    let proteins = Set(picked.map(\.protein).filter { !$0.isEmpty })
    let courses = Set(picked.map { $0.category.lowercased() })
    var cuisineCounts: [String: Int] = [:]
    for cuisine in picked.map({ $0.cuisine.uppercased() }) {
        cuisineCounts[cuisine, default: 0] += 1
    }
    check(cuisines.count >= 4, "bundled week should cover at least 4 countries, got \(week)")
    check(cuisineCounts.values.allSatisfy { $0 <= 2 }, "bundled week should not stack one cuisine, got \(cuisineCounts)")
    check(proteins.count >= 3, "bundled week should vary protein, got \(picked.map(\.protein))")
    check(courses.count >= 2, "bundled week should vary course, got \(picked.map(\.category))")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let recent = picked.map { RecentMealSighting(slug: $0.slug, at: now, wasCooked: false) }
    let rebuilt = MealRecommender.pick(
        candidates: candidates,
        evenings: 5,
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        recent: recent,
        now: now
    )
    check(Set(rebuilt).isDisjoint(with: Set(week)), "rebuilding the week should drop meals planned today, got \(rebuilt)")
    check(
        week == ["menemen", "mercimek-corbasi", "chapli-kebab", "fattoush", "draniki"],
        "fresh 60-minute catalog week, got \(week)"
    )
    check(
        rebuilt == ["iskender-kebab", "tarator", "dal-tadka", "tabbouleh", "moules-marinieres"],
        "catalog rebuild after planning that week, got \(rebuilt)"
    )
}

@main
struct RecommenderChecks {
    static func main() {
        checkFilters()
        checkLovedAndRecency()
        checkDiversitySignals()
        checkWeekAndReplace()
        checkProteinAndRegion()
        checkExposureLog()
        do {
            try checkBundledCatalog()
        } catch {
            failures += 1
            fputs("FAIL bundled catalog \(error)\n", stderr)
        }

        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("meal recommender checks passed")
    }
}
