import Foundation

/// Checks for recipe browse filters, replacement chips, preference insight,
/// evening labels, and the local analytics log.
///
///   Tools/run_product_gap_checks.sh

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { return }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func item(
    _ slug: String,
    name: String,
    minutes: Int = 40,
    protein: String = "",
    diets: Set<String> = [],
    tags: Set<String> = [],
    loved: Bool = false,
    country: String = "TR"
) -> RecipeBrowseItem {
    RecipeBrowseItem(
        slug: slug,
        displayName: name,
        nameEN: name,
        country: country,
        totalMinutes: minutes,
        protein: protein,
        diets: diets,
        tags: tags,
        isLoved: loved
    )
}

private func candidate(
    _ slug: String,
    minutes: Int,
    protein: String = "",
    diets: Set<String> = [],
    rating: MealRating? = nil,
    cuisine: String = "TR",
    category: String = "main",
    tags: Set<String> = [],
    ingredients: Set<String> = [],
    score: Int = 50
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
        diets: diets
    )
}

private func checkBrowse() {
    let catalog = [
        item("pilav", name: "Tavuklu pilav", minutes: 25, protein: "poultry", tags: ["rice", "quick"]),
        item("kebap", name: "Adana kebap", minutes: 50, protein: "red-meat", tags: ["grill"], loved: true),
        item("balik", name: "Izgara balık", minutes: 35, protein: "seafood", tags: ["grill"]),
        item("makarna", name: "Domatesli makarna", minutes: 30, protein: "", diets: ["vegetarian"], tags: ["pasta"]),
        item("firin", name: "Fırın mücver", minutes: 70, protein: "", diets: ["vegetarian"], tags: ["bake"]),
    ]
    let chicken = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .chicken)).map(\.slug)
    check(chicken == ["pilav"], "chicken chip \(chicken)")

    let beef = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .beef)).map(\.slug)
    check(beef == ["kebap"], "red meat chip \(beef)")

    let fish = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .fish)).map(\.slug)
    check(fish == ["balik"], "fish chip \(fish)")

    let vegetarian = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .vegetarian)).map(\.slug)
    check(vegetarian == ["makarna", "firin"], "vegetarian sort \(vegetarian)")

    let pasta = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .pasta)).map(\.slug)
    check(pasta == ["makarna"], "pasta tag \(pasta)")

    let rice = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .rice)).map(\.slug)
    check(rice == ["pilav"], "rice tag \(rice)")

    let oven = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .oven)).map(\.slug)
    check(oven == ["firin"], "oven tag \(oven)")

    let quick = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(category: .quick)).map(\.slug)
    check(Set(quick) == ["makarna", "pilav"], "quick is the tag or 30 minutes, got \(quick)")

    let halfHour = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(cookTime: .upTo30)).map(\.slug)
    check(Set(halfHour) == ["makarna", "pilav"], "30 minute filter \(halfHour)")

    let loved = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(lovedOnly: true)).map(\.slug)
    check(loved == ["kebap"], "loved filter \(loved)")

    let search = RecipeBrowse.filter(catalog, query: RecipeBrowseQuery(searchText: "balık")).map(\.slug)
    check(search == ["balik"], "search \(search)")

    let none = RecipeBrowse.filter(
        catalog,
        query: RecipeBrowseQuery(category: .fish, lovedOnly: true)
    )
    check(none.isEmpty, "fish plus loved should be empty")

    check(RecipeBrowseCategory.chicken.title == "Tavuk", "turkish chicken label")
    check(RecipeCookTimeFilter.upTo45.title == "45 dk", "turkish time label")
    check(!RecipeBrowseCategory.allCases.map(\.title).joined().contains("Chicken"), "category labels stay Turkish")
}

private func checkReplacement() {
    let current = candidate("tavuk", minutes: 50, protein: "poultry", ingredients: ["chicken"], score: 80)
    let catalog = [
        current,
        candidate("corba", minutes: 30, protein: "legume", cuisine: "TR", category: "soup", score: 70),
        candidate("balik", minutes: 40, protein: "seafood", cuisine: "GR", score: 60),
        candidate("kofte", minutes: 55, protein: "red-meat", score: 90),
        candidate("pilav", minutes: 20, protein: "poultry", ingredients: ["chicken"], score: 40),
        candidate("mercimek", minutes: 35, protein: "legume", diets: ["vegetarian"], rating: .loved, score: 65),
        candidate("asla", minutes: 25, protein: "tofu", diets: ["vegan"], rating: .never, score: 99),
        candidate("uzun", minutes: 80, protein: "egg", score: 10),
    ]

    let open = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: ["tavuk"],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: []
    ).map(\.slug)
    check(!open.contains("tavuk"), "current slug stays blocked")
    check(!open.contains("asla"), "never-again stays out \(open)")
    check(!open.contains("uzun"), "over the time cap stays out \(open)")
    check(open.contains("kofte"), "an in-cap alternative stays \(open)")

    let faster = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.faster]
    )
    check(faster.allSatisfy { $0.minutes < 50 }, "faster is strictly shorter \(faster)")
    check(!faster.map(\.slug).contains("kofte"), "55 minutes is not faster than 50")
    check(faster.contains { $0.reason == "Daha kısa sürer" }, "faster reason")

    let noChicken = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.noChicken]
    ).map(\.slug)
    check(!noChicken.contains("pilav") && !noChicken.contains("tavuk"), "no chicken \(noChicken)")

    let vegetarian = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 90,
        dislikedIngredientIds: [],
        activeChips: [.vegetarian]
    ).map(\.slug)
    check(vegetarian == ["mercimek"], "only the vegetarian that is not never-again \(vegetarian)")

    let loved = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.loved]
    )
    check(loved.map(\.slug) == ["mercimek"], "loved chip \(loved)")
    check(loved.first?.reason == "Sevdiğin bir yemeğe benziyor", "loved reason")

    let different = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.different]
    ).map(\.slug)
    check(!different.contains("pilav"), "different drops the same protein \(different)")

    let disliked = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: [],
        maxCookMinutes: 60,
        dislikedIngredientIds: ["chicken"],
        activeChips: []
    ).map(\.slug)
    check(!disliked.contains("pilav"), "disliked chicken ingredient \(disliked)")

    let surpriseA = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: ["tavuk"],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.surprise]
    )
    let surpriseB = MealReplacement.choices(
        catalog: catalog,
        current: current,
        blockedSlugs: ["tavuk"],
        maxCookMinutes: 60,
        dislikedIngredientIds: [],
        activeChips: [.surprise]
    )
    check(surpriseA.count == 1 && surpriseA == surpriseB, "surprise is one deterministic pick \(surpriseA)")
    check(surpriseA.first?.slug != "tavuk", "surprise is not the current meal")
    check(surpriseA.first?.reason == "Sürpriz bir alternatif", "surprise reason")

    let cleared = MealReplacement.toggled([.faster, .vegetarian], .surprise)
    check(cleared == [.surprise], "surprise replaces other chips \(cleared)")
    check(MealReplacement.toggled(cleared, .loved) == [.loved], "another chip leaves surprise")
    check(ReplacementChip.allCases.map(\.title).joined(separator: "|").contains("Daha hızlı"), "turkish faster chip")
}

private func checkInsight() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    check(PreferenceInsightBuilder.make(loved: [], now: now) == nil, "first use hides the card")
    let two = [
        LovedMealSample(protein: "poultry", createdAt: now),
        LovedMealSample(protein: "poultry", createdAt: now),
    ]
    check(PreferenceInsightBuilder.make(loved: two, now: now) == nil, "two loves are not enough")

    let chicken = PreferenceInsightBuilder.make(
        loved: [
            LovedMealSample(protein: "poultry", createdAt: now),
            LovedMealSample(protein: "poultry", createdAt: now.addingTimeInterval(-3_600)),
            LovedMealSample(protein: "seafood", createdAt: now.addingTimeInterval(-7_200)),
        ],
        now: now
    )
    check(chicken?.title == "Tercihlerin netleşiyor", "insight title")
    check(chicken?.message == "Son zamanlarda 2 tavuk tarifini sevdin.", "chicken insight \(chicken?.message ?? "")")

    let mixed = PreferenceInsightBuilder.make(
        loved: [
            LovedMealSample(protein: "poultry", createdAt: now),
            LovedMealSample(protein: "seafood", createdAt: now),
            LovedMealSample(protein: "legume", createdAt: now),
        ],
        now: now
    )
    check(mixed?.message == "Son zamanlarda 3 tarifi sevdin.", "generic insight \(mixed?.message ?? "")")
    check(mixed?.message.contains("Chicken") == false, "insight stays Turkish")
}

private func checkEveningLabels() {
    check(EveningCountOptions.values == [1, 2, 3, 4, 5], "evening choices")
    check(EveningCountOptions.label(1) == "1 akşam", "1")
    check(EveningCountOptions.label(2) == "2 akşam", "2")
    check(EveningCountOptions.label(4) == "4 akşam", "4")
    check(EveningCountOptions.label(5) == "5 akşam", "5")
    check(!EveningCountOptions.label(3).contains("Evening"), "labels stay Turkish")
}

private func checkAnalytics() {
    let expected: Set<String> = [
        "app_opened",
        "onboarding_started",
        "onboarding_completed",
        "recipe_rated",
        "recipe_loved",
        "recipe_disliked",
        "plan_generated",
        "plan_viewed",
        "meal_replaced",
        "recipe_opened",
        "meal_cooked",
        "meal_feedback_given",
        "grocery_opened",
        "grocery_item_checked",
        "grocery_list_completed",
    ]
    check(Set(AnalyticsEvent.allCases.map(\.rawValue)) == expected, "checklist event names")

    Analytics.resetForTests()
    Analytics.track(.mealReplaced, properties: [
        "email": "person@example.com",
        "displayName": "Ayşe",
        "note": String(repeating: "x", count: 80),
        "rating": "loved",
    ])
    let stored = Analytics.recent()
    check(stored.count == 1 && stored[0].name == "meal_replaced", "event name stored \(stored)")
    check(stored[0].properties == ["rating": "loved"], "pii and long values dropped \(stored[0].properties)")
    Analytics.trackOnce(.appOpened)
    Analytics.trackOnce(.appOpened)
    check(Analytics.recent().filter { $0.name == "app_opened" }.count == 1, "app open is once per launch")
    Analytics.resetForTests()
    check(Analytics.recent().isEmpty, "reset clears the buffer")
}

@main
struct ProductGapChecks {
    static func main() {
        checkBrowse()
        checkReplacement()
        checkInsight()
        checkEveningLabels()
        checkAnalytics()
        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("product gap checks passed")
    }
}
