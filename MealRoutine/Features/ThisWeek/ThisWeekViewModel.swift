import Foundation
import Observation
import SwiftData

struct WeekMealPresentation: Identifiable, Equatable {
    var id: UUID
    var dayTitle: String
    var dateTitle: String
    var recipeName: String
    var minutes: Int
    var difficultyTitle: String
    var servings: Int
    var isCooked: Bool
    var isToday: Bool
    var rating: MealRating?
    var slug: String
    var reason: String = ""
    var badgeTitle: String?
    var isSkipped: Bool = false

    /// Cooked meals do not offer Atladım. Cook wins if both flags were set.
    var showsSkip: Bool { SkipControl.showsAffordance(isCooked: isCooked) }

    /// Skipped chrome stays off once the meal is cooked.
    var showsSkippedChrome: Bool { isSkipped && showsSkip }
}

struct WeekSummaryPresentation: Equatable {
    var planned: Int
    var cooked: Int
    var loved: Int
}

@MainActor
@Observable
final class ThisWeekViewModel {
    var alertMessage: String?
    var isWorking = false

    /// Today's planned evening, or the next uncooked slot when today is not on the plan.
    func featuredEvening(in meals: [WeekMealPresentation]) -> WeekMealPresentation? {
        if let today = meals.first(where: \.isToday) { return today }
        if let upcoming = meals.first(where: { !$0.isCooked }) { return upcoming }
        return meals.last
    }

    func featuredEveningTitle(for meal: WeekMealPresentation) -> String {
        if meal.isToday { return "Bu akşam" }
        if meal.isCooked { return "Son akşam" }
        return "Sıradaki akşam"
    }

    func preferenceInsight(
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        now: Date = .now
    ) -> PreferenceInsight? {
        let catalog = WeekPlanService.pickerCandidates(from: recipes, ratings: [:])
        let proteinBySlug = Dictionary(uniqueKeysWithValues: catalog.map { ($0.slug, $0.protein) })
        var latest: [String: (date: Date, rating: MealRating)] = [:]
        for item in feedback {
            if let existing = latest[item.recipeSlug], existing.date > item.createdAt {
                continue
            }
            latest[item.recipeSlug] = (item.createdAt, item.rating)
        }
        let loved = latest.compactMap { slug, value -> LovedMealSample? in
            guard value.rating == .loved else { return nil }
            return LovedMealSample(protein: proteinBySlug[slug] ?? "", createdAt: value.date)
        }
        return PreferenceInsightBuilder.make(loved: loved, now: now)
    }

    func summary(meals: [WeekMealPresentation]) -> WeekSummaryPresentation {
        WeekSummaryPresentation(
            planned: meals.count,
            cooked: meals.filter(\.isCooked).count,
            loved: meals.filter { $0.rating == .loved }.count
        )
    }

    func explanation(weeks: [PlanWeek], now: Date = .now) -> String {
        let start = WeekCalendar.weekStart(containing: now)
        return weeks.first { WeekCalendar.isSameDay($0.weekStart, start) }?.explanation ?? ""
    }

    func meals(
        weeks: [PlanWeek],
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        householdSize: Int,
        memories: [MealMemory] = [],
        prefs: UserPrefs? = nil,
        now: Date = .now
    ) -> [WeekMealPresentation] {
        let start = WeekCalendar.weekStart(containing: now)
        guard let week = weeks.first(where: { WeekCalendar.isSameDay($0.weekStart, start) }) else {
            return []
        }
        let names = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let catalog = WeekPlanService.pickerCandidates(from: recipes, ratings: ratings)
        let memoryMap = Dictionary(memories.map { ($0.recipeSlug, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let storedPrefs = prefs
        let planning = storedPrefs?.planningPreferences ?? PlanningPreferences.standard(
            maxCookMinutes: CookTimeOptions.defaultMinutes
        )
        let taste = PersonalizedScoringService.profile(memories: memoryMap, candidates: catalog)
        let hasHistory = taste.dataPointCount > 0
        return week.meals
            .sorted { $0.dayOffset < $1.dayOffset }
            .map { meal in
                let recipe = names[meal.recipeSlug]
                let date = WeekCalendar.date(weekStart: week.weekStart, dayOffset: meal.dayOffset)
                let candidate = catalog.first { $0.slug == meal.recipeSlug }
                let memory = memoryMap[meal.recipeSlug]
                let reason = candidate.flatMap {
                    RecommendationReasonService.personalReason(
                        for: $0,
                        memory: memory,
                        profile: taste,
                        catalog: catalog
                    )
                } ?? ""
                let badge = RecommendationReasonService.badge(for: memory, hasHistory: hasHistory)
                return WeekMealPresentation(
                    id: meal.uuid,
                    dayTitle: WeekCalendar.dayTitle(offset: meal.dayOffset),
                    dateTitle: WeekCalendar.shortDate(date),
                    recipeName: recipe?.displayName ?? meal.recipeSlug,
                    minutes: recipe?.totalMinutes ?? 0,
                    difficultyTitle: DifficultyLabel.turkish(recipe?.difficulty ?? ""),
                    servings: ActiveServings.resolve(
                        mealServings: meal.servings,
                        householdSize: householdSize
                    ),
                    isCooked: meal.cookedAt != nil,
                    isToday: WeekCalendar.isSameDay(date, now),
                    rating: ratings[meal.recipeSlug],
                    slug: meal.recipeSlug,
                    reason: reason,
                    badgeTitle: badge?.title,
                    isSkipped: SkipControl.recordsAsSkipped(skippedAt: meal.skippedAt, cookedAt: meal.cookedAt)
                )
            }
    }

    func ensureWeek(in context: ModelContext) {
        do {
            _ = try WeekPlanService.ensureCurrentWeek(in: context)
            try GroceryListService.rebuild(in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func skip(uuid: UUID, in context: ModelContext) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try WeekPlanService.markSkipped(uuid: uuid, in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func dismissPattern(_ id: String, in context: ModelContext) {
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else { return }
            if !prefs.dismissedPatternIDs.contains(id) {
                prefs.dismissedPatternIDs.append(id)
            }
            try context.save()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func regenerate(in context: ModelContext) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let prefs = try UserPrefsStore.existing(in: context) else {
                alertMessage = WeekPlanError.missingPreferences.errorDescription
                return
            }
            let request = WeekPlanService.planRequest(from: prefs)
            _ = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            try GroceryListService.rebuild(in: context)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

}

struct ReplacementChoicePresentation: Identifiable, Equatable {
    var slug: String
    var name: String
    var minutes: Int
    var difficultyTitle: String
    var categoryTitle: String
    var reason: String
    var photoURL: String
    var photoAuthor: String
    var photoLicense: String

    var id: String { slug }
}

struct ReplacementBoard: Equatable {
    var currentName: String
    var choices: [ReplacementChoicePresentation]
}

enum ReplacementPresenter {
    static func board(
        mealID: UUID,
        chips: Set<ReplacementChip>,
        weeks: [PlanWeek],
        recipes: [Recipe],
        feedback: [RecipeFeedback],
        prefs: [UserPrefs],
        memories: [MealMemory] = [],
        now: Date = .now
    ) -> ReplacementBoard {
        let start = WeekCalendar.weekStart(containing: now)
        guard let week = weeks.first(where: { WeekCalendar.isSameDay($0.weekStart, start) }),
              let meal = week.meals.first(where: { $0.uuid == mealID }) else {
            return ReplacementBoard(currentName: "", choices: [])
        }
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let catalog = WeekPlanService.pickerCandidates(from: recipes, ratings: ratings)
        let bySlug = Dictionary(recipes.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let currentName = bySlug[meal.recipeSlug]?.displayName ?? meal.recipeSlug
        guard let current = catalog.first(where: { $0.slug == meal.recipeSlug }) else {
            return ReplacementBoard(currentName: currentName, choices: [])
        }
        let blocked = Set(week.meals.map(\.recipeSlug))
        let anchors = catalog.filter { blocked.contains($0.slug) }
        let stored = prefs.min { $0.createdAt < $1.createdAt }
        let memoryMap = Dictionary(memories.map { ($0.recipeSlug, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let picked = MealReplacement.choices(
            catalog: catalog,
            current: current,
            blockedSlugs: blocked,
            maxCookMinutes: CookTimeOptions.resolved(stored?.maxCookMinutes ?? CookTimeOptions.defaultMinutes),
            dislikedIngredientIds: Set(stored?.dislikedIngredientIds ?? []),
            activeChips: chips,
            anchors: anchors,
            memory: ReplacementMemory(
                memories: memoryMap,
                preferences: stored?.planningPreferences,
                dayOffset: meal.dayOffset,
                now: now
            )
        )
        let choices = picked.map { choice in
            let recipe = bySlug[choice.slug]
            return ReplacementChoicePresentation(
                slug: choice.slug,
                name: recipe?.displayName ?? choice.slug,
                minutes: choice.minutes,
                difficultyTitle: DifficultyLabel.turkish(recipe?.difficulty ?? ""),
                categoryTitle: CategoryLabel.turkish(recipe?.unitoolsCategory ?? ""),
                reason: choice.reason,
                photoURL: recipe?.photoURL ?? "",
                photoAuthor: recipe?.photoAuthor ?? "",
                photoLicense: recipe?.photoLicense ?? ""
            )
        }
        return ReplacementBoard(currentName: currentName, choices: choices)
    }
}
