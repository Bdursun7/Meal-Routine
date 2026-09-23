import Foundation
import Observation
import SwiftData

struct IngredientChip: Identifiable, Equatable {
    var id: String
    var name: String
    /// Catalog ids written to prefs when this chip is selected.
    var ingredientIds: [String]
}

/// One visible dislike chip that stores more than one catalog id.
enum DislikeChipMerge {
    struct Group: Equatable {
        var chipID: String
        var name: String
        var ingredientIDs: [String]
    }

    /// `egg` and `eggs` are separate UniTools ids. The chip shows one “Yumurta”.
    static let groups: [Group] = [
        Group(chipID: "egg", name: "Yumurta", ingredientIDs: ["egg", "eggs"])
    ]

    static func group(containing ingredientID: String) -> Group? {
        groups.first { $0.ingredientIDs.contains(ingredientID) }
    }
}

enum OnboardingStep: Int, Equatable {
    case welcome = 0
    case household = 1
    case dislikes = 2
    case taste = 3
    case summary = 4

    static let progressTotal = 4

    var title: String {
        switch self {
        case .welcome: ""
        case .household: "Ev"
        case .dislikes: "Sevmediğin malzemeler"
        case .taste: "Tat"
        case .summary: "Hazır mısın?"
        }
    }

    var showsProgress: Bool { self != .welcome }
}

/// Collects household prefs, optional dislikes, and an optional taste sample.
/// The week is created only from the summary CTA.
@MainActor
@Observable
final class OnboardingViewModel {
    static let tasteSampleLimit = 8

    var step: OnboardingStep = .welcome
    var householdSize = 2
    var evenings = MealRecommender.eveningCap
    var maxCookMinutes = CookTimeOptions.defaultMinutes
    var disliked: Set<String> = []
    var ratings: [String: MealRating] = [:]
    var chips: [IngredientChip] = []
    var isSaving = false
    var errorMessage: String?
    /// Set when Düzenle jumps backward. The next Devam / Atla returns to the summary.
    private var editingFromSummary = false

    /// Staples that are poor dislike chips.
    private let pantryIDs: Set<String> = [
        "salt", "oil", "pepper", "water", "blackpepper", "black-pepper"
    ]

    func loadChips(from recipes: [Recipe]) {
        guard chips.isEmpty, !recipes.isEmpty else { return }

        struct Tally {
            var name: String
            var count: Int
            var ingredientIDs: Set<String>
        }

        var tallies: [String: Tally] = [:]
        for recipe in recipes {
            var seen: Set<String> = []
            for line in recipe.ingredients {
                if let group = DislikeChipMerge.group(containing: line.ingredientId) {
                    guard seen.insert(group.chipID).inserted else { continue }
                    var tally = tallies[group.chipID] ?? Tally(
                        name: group.name,
                        count: 0,
                        ingredientIDs: Set(group.ingredientIDs)
                    )
                    tally.count += 1
                    tally.name = group.name
                    tally.ingredientIDs = Set(group.ingredientIDs)
                    tallies[group.chipID] = tally
                    continue
                }

                guard !pantryIDs.contains(line.ingredientId) else { continue }
                guard seen.insert(line.ingredientId).inserted else { continue }
                var tally = tallies[line.ingredientId] ?? Tally(
                    name: line.displayName,
                    count: 0,
                    ingredientIDs: [line.ingredientId]
                )
                tally.count += 1
                if tally.name.isEmpty { tally.name = line.displayName }
                tallies[line.ingredientId] = tally
            }
        }

        chips = tallies
            .map { key, value in
                IngredientChip(
                    id: key,
                    name: value.name,
                    ingredientIds: value.ingredientIDs.sorted()
                )
            }
            .sorted { lhs, rhs in
                let left = tallies[lhs.id]?.count ?? 0
                let right = tallies[rhs.id]?.count ?? 0
                if left != right { return left > right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(24)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func sampleRecipes(from recipes: [Recipe]) -> [Recipe] {
        recipes
            .sorted { lhs, rhs in
                if lhs.trDogfoodScore != rhs.trDogfoodScore {
                    return lhs.trDogfoodScore > rhs.trDogfoodScore
                }
                return lhs.slug < rhs.slug
            }
            .prefix(Self.tasteSampleLimit)
            .map { $0 }
    }

    func isDisliked(_ chip: IngredientChip) -> Bool {
        Set(chip.ingredientIds).isSubset(of: disliked)
    }

    /// Selecting a merged chip stores every catalog id on that chip.
    func toggleDislike(_ chip: IngredientChip) {
        let ids = Set(chip.ingredientIds)
        if ids.isSubset(of: disliked) {
            disliked.subtract(ids)
        } else {
            disliked.formUnion(ids)
        }
    }

    func continueForward() {
        errorMessage = nil
        if editingFromSummary, step != .summary {
            editingFromSummary = false
            step = .summary
            return
        }
        switch step {
        case .welcome: step = .household
        case .household: step = .dislikes
        case .dislikes: step = .taste
        case .taste: step = .summary
        case .summary: break
        }
    }

    /// Leaves any partial ratings in place and moves on.
    func skipTaste() {
        continueForward()
    }

    func goBack() {
        errorMessage = nil
        if editingFromSummary {
            editingFromSummary = false
            step = .summary
            return
        }
        switch step {
        case .welcome: break
        case .household: step = .welcome
        case .dislikes: step = .household
        case .taste: step = .dislikes
        case .summary: step = .taste
        }
    }

    func edit(_ step: OnboardingStep) {
        errorMessage = nil
        editingFromSummary = true
        self.step = step
    }

    var householdSummary: String {
        let people = householdSize == 1 ? "1 kişi" : "\(householdSize) kişi"
        return "\(people) · \(evenings) akşam · \(CookTimeOptions.label(maxCookMinutes))"
    }

    var dislikeSummary: String {
        let names = chips.filter { isDisliked($0) }.map(\.name)
        if names.isEmpty { return "Seçilmedi" }
        return names.joined(separator: ", ")
    }

    var tasteSummary: String {
        if ratings.isEmpty { return "Atlandı" }
        return "\(ratings.count) tarif işaretlendi"
    }

    func finish(in context: ModelContext) {
        guard !isSaving, step == .summary else { return }
        isSaving = true
        errorMessage = nil
        do {
            let prefs: UserPrefs
            if let existing = try UserPrefsStore.existing(in: context) {
                prefs = existing
            } else {
                prefs = UserPrefs()
                context.insert(prefs)
            }
            prefs.householdSize = HouseholdSizeLimits.clamped(householdSize)
            prefs.eveningsPerWeek = min(max(evenings, 1), MealRecommender.eveningCap)
            prefs.maxCookMinutes = CookTimeOptions.resolved(maxCookMinutes)
            prefs.dislikedIngredientIds = disliked.sorted()
            prefs.hasCompletedOnboarding = false
            try insertRatingsIfNeeded(in: context)
            try context.save()

            let request = WeekPlanService.planRequest(from: prefs)
            let week = try WeekPlanService.replaceCurrentWeek(in: context, request: request)
            let plannedCount = try plannedMealCount(for: week, in: context)
            guard plannedCount > 0 else {
                context.delete(week)
                try context.save()
                errorMessage = "Bu tercihlerle akşam çıkmadı. Pişirme süresini yükselt veya sevmediğin malzemeleri azalt."
                isSaving = false
                return
            }

            try GroceryListService.rebuild(in: context)
            prefs.hasCompletedOnboarding = true
            try context.save()
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func insertRatingsIfNeeded(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<RecipeFeedback>())
        let latest = FeedbackIndex.latestRatings(in: existing)
        for (slug, rating) in ratings where latest[slug] != rating {
            context.insert(RecipeFeedback(recipeSlug: slug, rating: rating, cooked: false))
        }
    }

    private func plannedMealCount(for week: PlanWeek, in context: ModelContext) throws -> Int {
        if !week.meals.isEmpty { return week.meals.count }
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        return meals.filter { $0.week?.uuid == week.uuid }.count
    }
}
