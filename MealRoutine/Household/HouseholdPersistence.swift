import Foundation
import SwiftData

/// Local cache of the household board. SwiftData is not the shared source of truth.
@Model
final class HouseholdCacheBox {
    var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String = HouseholdCacheBox.currentKey, payload: Data, updatedAt: Date) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }

    static let currentKey = "current"
    /// Test-mode client board. Kept apart from the CloudKit cache.
    static let testClientKey = "test-client"
    /// Encoded `FakeHouseholdBackendState` for the test-mode server.
    static let testServerKey = "test-server"
}

enum HouseholdAccountStore {
    private static let idKey = "mealroutine.appleUserID"
    private static let nameKey = "mealroutine.appleDisplayName"
    private static let createdKey = "mealroutine.appleCreatedAt"
    private static let testIDKey = "mealroutine.testUserID"
    private static let testNameKey = "mealroutine.testDisplayName"
    private static let testCreatedKey = "mealroutine.testCreatedAt"

    static func load(testMode: Bool = false) -> HouseholdUser? {
        let defaults = UserDefaults.standard
        let idKey = testMode ? testIDKey : self.idKey
        let nameKey = testMode ? testNameKey : self.nameKey
        let createdKey = testMode ? testCreatedKey : self.createdKey
        guard let id = defaults.string(forKey: idKey), !id.isEmpty else { return nil }
        let name = defaults.string(forKey: nameKey) ?? ""
        let created = Date(timeIntervalSince1970: defaults.double(forKey: createdKey))
        return HouseholdUser(id: id, displayName: name, createdAt: created == .distantPast || defaults.double(forKey: createdKey) == 0 ? .now : created)
    }

    static func save(_ user: HouseholdUser, testMode: Bool = false) {
        let defaults = UserDefaults.standard
        defaults.set(user.id, forKey: testMode ? testIDKey : idKey)
        defaults.set(user.displayName, forKey: testMode ? testNameKey : nameKey)
        defaults.set(user.createdAt.timeIntervalSince1970, forKey: testMode ? testCreatedKey : createdKey)
    }

    static func clear(testMode: Bool = false) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: testMode ? testIDKey : idKey)
        defaults.removeObject(forKey: testMode ? testNameKey : nameKey)
        defaults.removeObject(forKey: testMode ? testCreatedKey : createdKey)
    }
}

enum HouseholdCacheStore {
    @MainActor
    static func load(in context: ModelContext, key: String = HouseholdCacheBox.currentKey) -> HouseholdSnapshot {
        guard let box = existing(in: context, key: key),
              let snapshot = try? HouseholdCodec.decode(box.payload) else {
            return .empty()
        }
        return snapshot
    }

    @MainActor
    static func save(_ snapshot: HouseholdSnapshot, in context: ModelContext, key: String = HouseholdCacheBox.currentKey) {
        do {
            let data = try HouseholdCodec.encode(snapshot)
            saveData(data, updatedAt: snapshot.updatedAt, in: context, key: key)
        } catch {
            // The in-memory board stays usable when the cache row cannot be written.
        }
    }

    @MainActor
    static func loadData(in context: ModelContext, key: String) -> Data? {
        existing(in: context, key: key)?.payload
    }

    @MainActor
    static func saveData(_ data: Data, updatedAt: Date = .now, in context: ModelContext, key: String) {
        if let box = existing(in: context, key: key) {
            box.payload = data
            box.updatedAt = updatedAt
        } else {
            context.insert(HouseholdCacheBox(key: key, payload: data, updatedAt: updatedAt))
        }
        try? context.save()
    }

    @MainActor
    static func clear(in context: ModelContext, key: String) {
        guard let box = existing(in: context, key: key) else { return }
        context.delete(box)
        try? context.save()
    }

    @MainActor
    private static func existing(in context: ModelContext, key: String) -> HouseholdCacheBox? {
        let storedKey = key
        var descriptor = FetchDescriptor<HouseholdCacheBox>(
            predicate: #Predicate { $0.key == storedKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

struct HouseholdMealChrome: Equatable, Sendable {
    var rows: [HouseholdReactionRow]
    var label: HouseholdCompatibilityLabel
    var needsDecision: Bool
    var myReaction: MealReactionKind?
}

struct HouseholdReactionRow: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var symbol: String
}

enum HouseholdWeekPresenter {
    static func chrome(
        mealID: UUID,
        snapshot: HouseholdSnapshot,
        userId: String?
    ) -> HouseholdMealChrome? {
        guard snapshot.hasHousehold, let meal = snapshot.plan?.meals.first(where: { $0.id == mealID }) else {
            return nil
        }
        let memberIds = snapshot.members.map(\.userId)
        let rows = snapshot.members.map { member in
            let reaction = meal.reactions.first { $0.userId == member.userId }?.reaction
            return HouseholdReactionRow(
                id: member.userId,
                name: member.displayName,
                symbol: reaction?.symbol ?? "·"
            )
        }
        return HouseholdMealChrome(
            rows: rows,
            label: HouseholdConflict.label(reactions: meal.reactions, memberIds: memberIds),
            needsDecision: HouseholdConflict.needsDecision(meal.reactions),
            myReaction: userId.flatMap { id in meal.reactions.first { $0.userId == id }?.reaction }
        )
    }
}

enum HouseholdPlanBridge {
    @MainActor
    static func apply(snapshot: HouseholdSnapshot, in context: ModelContext, now: Date = .now) throws {
        guard let plan = snapshot.plan else { return }
        guard WeekCalendar.isSameDay(plan.weekStart, WeekCalendar.weekStart(containing: now)) else { return }
        guard let prefs = try UserPrefsStore.existing(in: context) else { return }
        if let existing = try WeekPlanService.currentWeek(in: context, now: now) {
            let retired = Set(existing.meals.map(\.uuid))
            let checks = try context.fetch(FetchDescriptor<IngredientCheck>())
            for check in checks {
                guard let mealUUID = check.mealUUID, retired.contains(mealUUID) else { continue }
                context.delete(check)
            }
            for meal in existing.meals { context.delete(meal) }
            for item in existing.groceries { context.delete(item) }
            context.delete(existing)
            try context.save()
        }
        let week = PlanWeek(weekStart: plan.weekStart, householdSize: prefs.householdSize)
        week.explanation = "Bu hafta \(HouseholdWeekCopy.headline(members: snapshot.members)) için kuruldu."
        context.insert(week)
        for shared in plan.meals.sorted(by: { $0.dayOffset < $1.dayOffset }) {
            let meal = PlannedMeal(
                uuid: shared.id,
                dayOffset: shared.dayOffset,
                recipeSlug: shared.recipeSlug,
                servings: prefs.householdSize,
                cookedAt: shared.cookedAt
            )
            meal.titleSnapshot = shared.title
            context.insert(meal)
            meal.week = week
        }
        try context.save()
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context, now: now)
        try applyGrocery(snapshot, in: context, now: now)
    }

    /// Partner recipes are not copied into the local collection. The evening still points at the slug.
    @MainActor
    static func assignSharedSlug(mealID: UUID, slug: String, title: String, in context: ModelContext) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        guard let meal = meals.first(where: { $0.uuid == mealID }) else { throw HouseholdError.mealNotFound }
        meal.recipeSlug = slug
        meal.titleSnapshot = title
        meal.cookedAt = nil
        try context.save()
    }

    @MainActor
    static func applyGrocery(_ snapshot: HouseholdSnapshot, in context: ModelContext, now: Date = .now) throws {
        guard snapshot.hasHousehold, let week = try WeekPlanService.currentWeek(in: context, now: now) else { return }
        let byKey = Dictionary(uniqueKeysWithValues: snapshot.groceryCompletions.map { ($0.itemKey, $0) })
        var changed = false
        for item in week.groceries {
            let key = HouseholdGroceryKey.make(
                ingredientId: item.ingredientId,
                unit: item.unit,
                isManual: item.isManual,
                uuid: item.uuid
            )
            guard let completion = byKey[key], completion.isChecked != item.isChecked else { continue }
            item.isChecked = completion.isChecked
            changed = true
        }
        if changed { try context.save() }
    }

    @MainActor
    static func candidates(recipes: [Recipe], ratings: [String: MealRating], projections: [HouseholdRecipeProjection]) -> [PickerCandidate] {
        var rows = WeekPlanService.pickerCandidates(from: recipes, ratings: ratings)
        let known = Set(rows.map(\.slug))
        for projection in HouseholdRecipeAccess.visibleForPlanning(projections) where !known.contains(projection.slug) {
            rows.append(
                PickerCandidate(
                    slug: projection.slug,
                    totalMinutes: max(projection.totalMinutes, 1),
                    trDogfoodScore: 48,
                    ingredientIds: Set(projection.ingredientIds),
                    rating: nil,
                    cuisine: projection.cuisine,
                    category: projection.category,
                    tags: [],
                    protein: projection.protein,
                    diets: Set(projection.diets),
                    difficulty: "",
                    timeIsUnknown: projection.totalMinutes <= 0,
                    importInterest: true
                )
            )
        }
        return rows
    }

    @MainActor
    static func projections(from recipes: [Recipe], ownerId: String) -> [HouseholdRecipeProjection] {
        recipes.compactMap { recipe in
            guard !recipe.isBundledCatalog, recipe.collectionState == .readyToCook else { return nil }
            let ids = recipe.ingredients.map(\.ingredientId)
            return HouseholdRecipeProjection(
                slug: recipe.slug,
                ownerUserId: ownerId,
                title: recipe.displayName,
                totalMinutes: recipe.totalMinutes,
                ingredientIds: ids,
                protein: MealRecommender.proteinFamily(in: ids),
                category: recipe.unitoolsCategory.isEmpty ? recipe.category : recipe.unitoolsCategory,
                cuisine: recipe.country,
                diets: recipe.diets,
                isReadyToCook: true,
                revision: 1,
                baseRevision: 0
            )
        }
    }
}
