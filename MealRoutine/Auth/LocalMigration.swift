import Foundation
import SwiftData

enum LocalMigrationPhase: String, Codable, Sendable {
    case notStarted
    case uploading
    case verifying
    case done
    case failed
}

struct LocalMigrationRecord: Codable, Equatable, Sendable {
    var phase: LocalMigrationPhase
    var recipes: Int
    var memories: Int
    var history: Int
    var message: String

    static let initial = LocalMigrationRecord(
        phase: .notStarted,
        recipes: 0,
        memories: 0,
        history: 0,
        message: ""
    )

    var headline: String {
        switch phase {
        case .notStarted:
            "Kişisel veriler henüz aktarılmadı."
        case .uploading, .verifying:
            "Verilerin hesabına aktarılıyor"
        case .done:
            "Aktarım tamam. Yerel veriler duruyor."
        case .failed:
            message.isEmpty ? "Aktarım yarım kaldı." : message
        }
    }
}

enum LocalMigrationMachine {
    static func start(_ record: LocalMigrationRecord) -> LocalMigrationRecord {
        guard record.phase != .done else { return record }
        var copy = record
        copy.phase = .uploading
        copy.message = ""
        return copy
    }

    static func uploaded(_ record: LocalMigrationRecord, counts: MigrationCounts) -> LocalMigrationRecord {
        var copy = record
        copy.phase = .verifying
        copy.recipes = counts.recipes
        copy.memories = counts.memories
        copy.history = counts.history
        return copy
    }

    static func verified(_ record: LocalMigrationRecord, counts: MigrationCounts) -> LocalMigrationRecord {
        var copy = record
        copy.phase = .done
        copy.recipes = counts.recipes
        copy.memories = counts.memories
        copy.history = counts.history
        copy.message = ""
        return copy
    }

    static func failed(_ record: LocalMigrationRecord, message: String) -> LocalMigrationRecord {
        var copy = record
        copy.phase = .failed
        copy.message = message
        return copy
    }

    static func markEmpty(_ record: LocalMigrationRecord) -> LocalMigrationRecord {
        var copy = record
        copy.phase = .done
        copy.message = ""
        return copy
    }
}

enum LocalMigrationGate {
    static func blocksHousehold(
        testMode: Bool,
        apiConfigured: Bool,
        signedIn: Bool,
        phase: LocalMigrationPhase,
        hasEligibleData: Bool
    ) -> Bool {
        apiConfigured && !testMode && signedIn && hasEligibleData && phase != .done
    }
}

struct MigrationCounts: Codable, Equatable, Sendable {
    var recipes: Int
    var memories: Int
    var favorites: Int
    var history: Int
    var feedback: Int
}

struct MigrationPayload: Codable, Equatable, Sendable {
    var preferences: MigrationPreferencePayload?
    var recipes: [MigrationRecipePayload]
    var memories: [MigrationMemoryPayload]
    var favorites: [MigrationFavoritePayload]
    var history: [MigrationHistoryPayload]
    var feedback: [MigrationFeedbackPayload]
}

struct MigrationPreferencePayload: Codable, Equatable, Sendable {
    var updatedAt: String
    var householdSize: Int
    var eveningsPerWeek: Int
    var maxCookMinutes: Int
    var dislikedIngredientIds: [String]
    var discoveryLevel: String
    var repeatPreference: String
    var difficultyPreference: String
    var weekdayStyle: String
    var dismissedPatternIds: [String]
    var hasCompletedOnboarding: Bool
}

struct MigrationRecipePayload: Codable, Equatable, Sendable {
    var id: String
    var slug: String
    var updatedAt: String
    var nameTr: String
    var nameEn: String
    var summaryTr: String
    var origin: String
    var collectionState: String
    var sourceUrl: String
    var sourceKey: String
    var sourcePlatform: String
    var sourceTitle: String
    var userNotes: String
    var baseServings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var totalMinutes: Int
    var timeIsUnknown: Bool
    var servingsUnspecified: Bool
    var difficulty: String
    var category: String
    var country: String
    var diets: [String]
    var tags: [String]
    var photoUrl: String
    var ingredients: [MigrationIngredientPayload]
    var steps: [MigrationStepPayload]
}

struct MigrationIngredientPayload: Equatable, Sendable {
    var id: String
    var sortIndex: Int
    var ingredientId: String
    var nameTr: String
    var nameEn: String
    var quantity: Double?
    var unit: String
    var noteTr: String
    var isOptional: Bool
    var includeInGrocery: Bool
}

extension MigrationIngredientPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, sortIndex, ingredientId, nameTr, nameEn, quantity, unit, noteTr, isOptional, includeInGrocery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sortIndex = try container.decode(Int.self, forKey: .sortIndex)
        ingredientId = try container.decode(String.self, forKey: .ingredientId)
        nameTr = try container.decode(String.self, forKey: .nameTr)
        nameEn = try container.decode(String.self, forKey: .nameEn)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decode(String.self, forKey: .unit)
        noteTr = try container.decode(String.self, forKey: .noteTr)
        isOptional = try container.decode(Bool.self, forKey: .isOptional)
        includeInGrocery = try container.decode(Bool.self, forKey: .includeInGrocery)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(ingredientId, forKey: .ingredientId)
        try container.encode(nameTr, forKey: .nameTr)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encodeNilAsNull(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        try container.encode(noteTr, forKey: .noteTr)
        try container.encode(isOptional, forKey: .isOptional)
        try container.encode(includeInGrocery, forKey: .includeInGrocery)
    }
}

struct MigrationStepPayload: Equatable, Sendable {
    var id: String
    var sortIndex: Int
    var textTr: String
    var textEn: String
    var minutes: Int?
}

extension MigrationStepPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, sortIndex, textTr, textEn, minutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sortIndex = try container.decode(Int.self, forKey: .sortIndex)
        textTr = try container.decode(String.self, forKey: .textTr)
        textEn = try container.decode(String.self, forKey: .textEn)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(textTr, forKey: .textTr)
        try container.encode(textEn, forKey: .textEn)
        try container.encodeNilAsNull(minutes, forKey: .minutes)
    }
}

struct MigrationMemoryPayload: Equatable, Sendable {
    var recipeSlug: String
    var updatedAt: String
    var timesCooked: Int
    var timesReplaced: Int
    var timesSkipped: Int
    var lastCookedAt: String?
    var lastSelectedAt: String?
    var lovedCount: Int
    var okayCount: Int
    var latestRating: String
    var neverAgain: Bool
    var timeConcernCount: Int
    var difficultyConcernCount: Int
    var portionConcernCount: Int
    var missingIngredientCount: Int
    var tooManyIngredientCount: Int
    var wouldMakeAgainCount: Int
    var isFavorite: Bool
    var discoveryStatus: String
    var confidence: String
}

extension MigrationMemoryPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case recipeSlug, updatedAt, timesCooked, timesReplaced, timesSkipped
        case lastCookedAt, lastSelectedAt, lovedCount, okayCount, latestRating, neverAgain
        case timeConcernCount, difficultyConcernCount, portionConcernCount
        case missingIngredientCount, tooManyIngredientCount, wouldMakeAgainCount
        case isFavorite, discoveryStatus, confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipeSlug = try container.decode(String.self, forKey: .recipeSlug)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        timesCooked = try container.decode(Int.self, forKey: .timesCooked)
        timesReplaced = try container.decode(Int.self, forKey: .timesReplaced)
        timesSkipped = try container.decode(Int.self, forKey: .timesSkipped)
        lastCookedAt = try container.decodeIfPresent(String.self, forKey: .lastCookedAt)
        lastSelectedAt = try container.decodeIfPresent(String.self, forKey: .lastSelectedAt)
        lovedCount = try container.decode(Int.self, forKey: .lovedCount)
        okayCount = try container.decode(Int.self, forKey: .okayCount)
        latestRating = try container.decode(String.self, forKey: .latestRating)
        neverAgain = try container.decode(Bool.self, forKey: .neverAgain)
        timeConcernCount = try container.decode(Int.self, forKey: .timeConcernCount)
        difficultyConcernCount = try container.decode(Int.self, forKey: .difficultyConcernCount)
        portionConcernCount = try container.decode(Int.self, forKey: .portionConcernCount)
        missingIngredientCount = try container.decode(Int.self, forKey: .missingIngredientCount)
        tooManyIngredientCount = try container.decode(Int.self, forKey: .tooManyIngredientCount)
        wouldMakeAgainCount = try container.decode(Int.self, forKey: .wouldMakeAgainCount)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        discoveryStatus = try container.decode(String.self, forKey: .discoveryStatus)
        confidence = try container.decode(String.self, forKey: .confidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recipeSlug, forKey: .recipeSlug)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(timesCooked, forKey: .timesCooked)
        try container.encode(timesReplaced, forKey: .timesReplaced)
        try container.encode(timesSkipped, forKey: .timesSkipped)
        try container.encodeNilAsNull(lastCookedAt, forKey: .lastCookedAt)
        try container.encodeNilAsNull(lastSelectedAt, forKey: .lastSelectedAt)
        try container.encode(lovedCount, forKey: .lovedCount)
        try container.encode(okayCount, forKey: .okayCount)
        try container.encode(latestRating, forKey: .latestRating)
        try container.encode(neverAgain, forKey: .neverAgain)
        try container.encode(timeConcernCount, forKey: .timeConcernCount)
        try container.encode(difficultyConcernCount, forKey: .difficultyConcernCount)
        try container.encode(portionConcernCount, forKey: .portionConcernCount)
        try container.encode(missingIngredientCount, forKey: .missingIngredientCount)
        try container.encode(tooManyIngredientCount, forKey: .tooManyIngredientCount)
        try container.encode(wouldMakeAgainCount, forKey: .wouldMakeAgainCount)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(discoveryStatus, forKey: .discoveryStatus)
        try container.encode(confidence, forKey: .confidence)
    }
}

struct MigrationFavoritePayload: Codable, Equatable, Sendable {
    var recipeSlug: String
    var createdAt: String
}

struct MigrationHistoryPayload: Equatable, Sendable {
    var id: String
    var recipeSlug: String
    var eventType: String
    var planWeekId: String?
    var plannedMealId: String?
    var replacementReason: String
    var createdAt: String
}

extension MigrationHistoryPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, recipeSlug, eventType, planWeekId, plannedMealId, replacementReason, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        recipeSlug = try container.decode(String.self, forKey: .recipeSlug)
        eventType = try container.decode(String.self, forKey: .eventType)
        planWeekId = try container.decodeIfPresent(String.self, forKey: .planWeekId)
        plannedMealId = try container.decodeIfPresent(String.self, forKey: .plannedMealId)
        replacementReason = try container.decode(String.self, forKey: .replacementReason)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recipeSlug, forKey: .recipeSlug)
        try container.encode(eventType, forKey: .eventType)
        try container.encodeNilAsNull(planWeekId, forKey: .planWeekId)
        try container.encodeNilAsNull(plannedMealId, forKey: .plannedMealId)
        try container.encode(replacementReason, forKey: .replacementReason)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension KeyedEncodingContainer {
    /// The upload schema requires these keys. A missing key is `invalid_request`; JSON null is accepted.
    mutating func encodeNilAsNull<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

struct MigrationFeedbackPayload: Codable, Equatable, Sendable {
    var id: String
    var recipeSlug: String
    var rating: String
    var cooked: Bool
    var reasons: [String]
    var createdAt: String
}

enum StableClientID {
    static func recipe(slug: String) -> UUID {
        uuid(for: "mealroutine.recipe.v1.\(slug)")
    }

    static func child(parent: UUID, kind: String, index: Int) -> UUID {
        uuid(for: "mealroutine.\(kind).v1.\(parent.uuidString).\(index)")
    }

    private static func uuid(for text: String) -> UUID {
        var digest = [UInt8](repeating: 0, count: 16)
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x100000001b3
        for byte in text.utf8 {
            first ^= UInt64(byte)
            first &*= 0x100000001b3
            second ^= UInt64(byte)
            second &*= 0xcbf29ce484222325
        }
        write(first, into: &digest, at: 0)
        write(second, into: &digest, at: 8)
        digest[6] = (digest[6] & 0x0f) | 0x50
        digest[8] = (digest[8] & 0x3f) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    private static func write(_ value: UInt64, into digest: inout [UInt8], at offset: Int) {
        var current = value
        for index in 0..<8 {
            digest[offset + index] = UInt8(current & 0xff)
            current >>= 8
        }
    }
}

enum MigrationSelection {
    static func includesRecipe(origin: String) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != RecipeOrigin.builtIn.rawValue
    }
}

@MainActor
enum MigrationCollector {
    static func hasEligible(
        recipes: [Recipe],
        memories: [MealMemory],
        events: [MealBehaviorEvent],
        feedback: [RecipeFeedback],
        prefs: [UserPrefs]
    ) -> Bool {
        if recipes.contains(where: { MigrationSelection.includesRecipe(origin: $0.originRaw) }) {
            return true
        }
        if memories.contains(where: { $0.snapshot.hasPersonalSignal }) { return true }
        if !events.isEmpty || !feedback.isEmpty { return true }
        return prefs.contains(where: isPersonalPreference)
    }

    static func payload(
        recipes: [Recipe],
        memories: [MealMemory],
        events: [MealBehaviorEvent],
        feedback: [RecipeFeedback],
        prefs: [UserPrefs]
    ) -> MigrationPayload {
        let preference = prefs.min { $0.createdAt < $1.createdAt }
        let personal = recipes.filter { MigrationSelection.includesRecipe(origin: $0.originRaw) }
        let memoryPayloads = memories.map(memoryPayload)
        return MigrationPayload(
            preferences: preference.map(preferencePayload),
            recipes: personal.map(recipePayload),
            memories: memoryPayloads,
            favorites: memoryPayloads.filter(\.isFavorite).map {
                MigrationFavoritePayload(recipeSlug: $0.recipeSlug, createdAt: $0.updatedAt)
            },
            history: events.map(historyPayload),
            feedback: feedback.map(feedbackPayload)
        )
    }

    static func snapshot(in context: ModelContext) -> (
        recipes: [Recipe],
        memories: [MealMemory],
        events: [MealBehaviorEvent],
        feedback: [RecipeFeedback],
        prefs: [UserPrefs]
    ) {
        (
            (try? context.fetch(FetchDescriptor<Recipe>())) ?? [],
            (try? context.fetch(FetchDescriptor<MealMemory>())) ?? [],
            (try? context.fetch(FetchDescriptor<MealBehaviorEvent>())) ?? [],
            (try? context.fetch(FetchDescriptor<RecipeFeedback>())) ?? [],
            (try? context.fetch(FetchDescriptor<UserPrefs>())) ?? []
        )
    }

    private static func isPersonalPreference(_ prefs: UserPrefs) -> Bool {
        prefs.hasCompletedOnboarding
            || !prefs.dislikedIngredientIds.isEmpty
            || prefs.difficultyPreference != .mostlyEasy
            || prefs.discoveryLevel != .balanced
            || prefs.repeatPreference != .balanced
            || prefs.weekdayStyle != .mostlyQuick
            || prefs.eveningsPerWeek != 7
            || prefs.maxCookMinutes != CookTimeOptions.defaultMinutes
            || prefs.householdSize != 2
            || !prefs.dismissedPatternIDs.isEmpty
    }

    private static func preferencePayload(_ prefs: UserPrefs) -> MigrationPreferencePayload {
        MigrationPreferencePayload(
            updatedAt: iso(prefs.createdAt),
            householdSize: prefs.householdSize,
            eveningsPerWeek: prefs.eveningsPerWeek,
            maxCookMinutes: prefs.maxCookMinutes,
            dislikedIngredientIds: prefs.dislikedIngredientIds,
            discoveryLevel: prefs.discoveryLevelRaw,
            repeatPreference: prefs.repeatPreferenceRaw,
            difficultyPreference: prefs.difficultyPreferenceRaw,
            weekdayStyle: prefs.weekdayStyleRaw,
            dismissedPatternIds: prefs.dismissedPatternIDs,
            hasCompletedOnboarding: prefs.hasCompletedOnboarding
        )
    }

    static func uploadPayload(for recipe: Recipe) -> MigrationPayload {
        let recipes = MigrationSelection.includesRecipe(origin: recipe.originRaw) ? [recipePayload(recipe)] : []
        return MigrationPayload(
            preferences: nil,
            recipes: recipes,
            memories: [],
            favorites: [],
            history: [],
            feedback: []
        )
    }

    static func recipePayload(_ recipe: Recipe) -> MigrationRecipePayload {
        let id = StableClientID.recipe(slug: recipe.slug)
        let stamps = [recipe.savedAt, recipe.importedAt, recipe.lastImportedAt, recipe.completedAt].compactMap { $0 }
        let ingredients = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
        let steps = recipe.steps.sorted { $0.sortIndex < $1.sortIndex }
        return MigrationRecipePayload(
            id: id.uuidString.lowercased(),
            slug: recipe.slug,
            updatedAt: iso(stamps.max() ?? Date(timeIntervalSince1970: 0)),
            nameTr: recipe.nameTR,
            nameEn: recipe.nameEN,
            summaryTr: recipe.summaryTR,
            origin: recipe.origin.rawValue,
            collectionState: recipe.collectionState.rawValue,
            sourceUrl: recipe.sourceURL,
            sourceKey: recipe.sourceKey,
            sourcePlatform: recipe.sourcePlatformRaw,
            sourceTitle: recipe.sourceTitle,
            userNotes: recipe.userNotes,
            baseServings: recipe.baseServings,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            totalMinutes: recipe.totalMinutes,
            timeIsUnknown: recipe.timeIsUnknown,
            servingsUnspecified: recipe.servingsUnspecified,
            difficulty: recipe.difficulty,
            category: recipe.category,
            country: recipe.country,
            diets: recipe.diets,
            tags: recipe.tags,
            photoUrl: recipe.photoURL,
            ingredients: ingredients.enumerated().map { index, line in
                MigrationIngredientPayload(
                    id: StableClientID.child(parent: id, kind: "ingredient", index: index).uuidString.lowercased(),
                    sortIndex: line.sortIndex,
                    ingredientId: line.ingredientId,
                    nameTr: line.nameTR,
                    nameEn: line.nameEN,
                    quantity: line.quantity,
                    unit: line.unit,
                    noteTr: line.noteTR,
                    isOptional: line.isOptional,
                    includeInGrocery: line.includeInGrocery
                )
            },
            steps: steps.enumerated().map { index, step in
                MigrationStepPayload(
                    id: StableClientID.child(parent: id, kind: "step", index: index).uuidString.lowercased(),
                    sortIndex: step.sortIndex,
                    textTr: step.textTR,
                    textEn: step.textEN,
                    minutes: step.minutes
                )
            }
        )
    }

    private static func memoryPayload(_ memory: MealMemory) -> MigrationMemoryPayload {
        let snapshot = memory.snapshot
        return MigrationMemoryPayload(
            recipeSlug: memory.recipeSlug,
            updatedAt: iso(memory.updatedAt),
            timesCooked: snapshot.timesCooked,
            timesReplaced: snapshot.timesReplaced,
            timesSkipped: snapshot.timesSkipped,
            lastCookedAt: snapshot.lastCookedAt.map(iso),
            lastSelectedAt: snapshot.lastSelectedAt.map(iso),
            lovedCount: snapshot.lovedCount,
            okayCount: snapshot.okayCount,
            latestRating: snapshot.latestRating?.rawValue ?? "",
            neverAgain: snapshot.neverAgain,
            timeConcernCount: snapshot.timeConcernCount,
            difficultyConcernCount: snapshot.difficultyConcernCount,
            portionConcernCount: snapshot.portionConcernCount,
            missingIngredientCount: snapshot.missingIngredientCount,
            tooManyIngredientCount: snapshot.tooManyIngredientCount,
            wouldMakeAgainCount: snapshot.wouldMakeAgainCount,
            isFavorite: snapshot.isFavorite,
            discoveryStatus: snapshot.discoveryStatus.rawValue,
            confidence: snapshot.confidence.rawValue
        )
    }

    private static func historyPayload(_ event: MealBehaviorEvent) -> MigrationHistoryPayload {
        MigrationHistoryPayload(
            id: event.uuid.uuidString.lowercased(),
            recipeSlug: event.recipeSlug,
            eventType: event.eventTypeRaw,
            planWeekId: event.planWeekID?.uuidString.lowercased(),
            plannedMealId: event.plannedMealID?.uuidString.lowercased(),
            replacementReason: event.replacementReason,
            createdAt: iso(event.createdAt)
        )
    }

    private static func feedbackPayload(_ feedback: RecipeFeedback) -> MigrationFeedbackPayload {
        MigrationFeedbackPayload(
            id: feedback.uuid.uuidString.lowercased(),
            recipeSlug: feedback.recipeSlug,
            rating: feedback.ratingRaw,
            cooked: feedback.cooked,
            reasons: feedback.reasonsRaw,
            createdAt: iso(feedback.createdAt)
        )
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct LocalMigrationStore {
    var defaults: UserDefaults

    func load(accountId: String) -> LocalMigrationRecord {
        guard let data = defaults.data(forKey: key(accountId)),
              let record = try? JSONDecoder().decode(LocalMigrationRecord.self, from: data) else {
            return .initial
        }
        return record
    }

    func save(accountId: String, record: LocalMigrationRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key(accountId))
    }

    private func key(_ accountId: String) -> String {
        "mealroutine.localMigration.\(accountId)"
    }
}

@MainActor
protocol MigrationTransport {
    func upload(_ payload: MigrationPayload) async throws -> MigrationCounts
    func confirm() async throws -> MigrationCounts
}

enum MigrationFailure: Error {
    case transport
    case rejected
}

@MainActor
final class FakeMigrationBackend: MigrationTransport {
    private var recipes: [String: String] = [:]
    private var memories = Set<String>()
    private var favorites = Set<String>()
    private var history = Set<String>()
    private var feedback = Set<String>()
    var failUploadsRemaining = 0

    var recipeCount: Int { recipes.count }
    var historyCount: Int { history.count }

    func upload(_ payload: MigrationPayload) async throws -> MigrationCounts {
        if failUploadsRemaining > 0 {
            failUploadsRemaining -= 1
            throw MigrationFailure.transport
        }
        for recipe in payload.recipes {
            recipes[recipe.slug] = recipe.id
        }
        for memory in payload.memories {
            memories.insert(memory.recipeSlug)
        }
        for favorite in payload.favorites {
            favorites.insert(favorite.recipeSlug)
        }
        for event in payload.history {
            history.insert(event.id)
        }
        for row in payload.feedback {
            feedback.insert(row.id)
        }
        return MigrationCounts(
            recipes: recipes.count,
            memories: memories.count,
            favorites: favorites.count,
            history: history.count,
            feedback: feedback.count
        )
    }

    func confirm() async throws -> MigrationCounts {
        MigrationCounts(
            recipes: recipes.count,
            memories: memories.count,
            favorites: favorites.count,
            history: history.count,
            feedback: feedback.count
        )
    }
}

@MainActor
struct MigrationHTTPClient: MigrationTransport {
    var session: URLSession
    var baseURL: URL
    var accessToken: String

    func upload(_ payload: MigrationPayload) async throws -> MigrationCounts {
        try await send(method: "POST", path: "/v1/migration/upload", body: payload)
    }

    func confirm() async throws -> MigrationCounts {
        try await send(method: "POST", path: "/v1/migration/confirm", body: nil as Data?)
    }

    private func send<Body: Encodable>(method: String, path: String, body: Body?) async throws -> MigrationCounts {
        guard let url = APIClient.url(baseURL: baseURL, path: path) else { throw MigrationFailure.transport }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MealRoutineConfig.clientAPIVersion, forHTTPHeaderField: "X-Client-API-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MigrationFailure.rejected
        }
        return try JSONDecoder().decode(MigrationStatusDTO.self, from: data).counts
    }
}

private struct MigrationStatusDTO: Codable {
    var status: String
    var counts: MigrationCounts
}

@MainActor
@Observable
final class LocalMigrationCenter {
    static let shared = LocalMigrationCenter()

    private(set) var record = LocalMigrationRecord.initial
    private(set) var hasEligibleData = false
    private var accountId = ""
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refresh(accountId: String?, in context: ModelContext) {
        guard !HouseholdTestMode.shared.isEnabled else {
            hasEligibleData = false
            return
        }
        guard let accountId, !accountId.isEmpty else {
            self.accountId = ""
            record = .initial
            hasEligibleData = false
            return
        }
        self.accountId = accountId
        record = LocalMigrationStore(defaults: defaults).load(accountId: accountId)
        let snapshot = MigrationCollector.snapshot(in: context)
        hasEligibleData = MigrationCollector.hasEligible(
            recipes: snapshot.recipes,
            memories: snapshot.memories,
            events: snapshot.events,
            feedback: snapshot.feedback,
            prefs: snapshot.prefs
        )
        if !hasEligibleData, record.phase != .done {
            record = LocalMigrationMachine.markEmpty(record)
            LocalMigrationStore(defaults: defaults).save(accountId: accountId, record: record)
        }
    }

    func runIfNeeded(in context: ModelContext) async {
        guard !HouseholdTestMode.shared.isEnabled else { return }
        guard MealRoutineConfig.apiBaseURL != nil else { return }
        guard let accountId = AuthSession.shared.account?.id else { return }
        refresh(accountId: accountId, in: context)
        guard hasEligibleData, record.phase != .done else { return }
        guard let baseURL = MealRoutineConfig.apiBaseURL,
              let token = AuthServices.sharedTokens.load()?.accessToken else { return }
        let client = MigrationHTTPClient(session: .shared, baseURL: baseURL, accessToken: token)
        await run(in: context, transport: client)
    }

    func runFake(in context: ModelContext) async {
        accountId = HouseholdTestPartner.localUserID
        record = .initial
        persist()
        await run(in: context, transport: FakeMigrationBackend())
    }

    func run(in context: ModelContext, transport: MigrationTransport) async {
        let snapshot = MigrationCollector.snapshot(in: context)
        let payload = MigrationCollector.payload(
            recipes: snapshot.recipes,
            memories: snapshot.memories,
            events: snapshot.events,
            feedback: snapshot.feedback,
            prefs: snapshot.prefs
        )
        await run(accountId: accountId, payload: payload, transport: transport)
    }

    func run(accountId: String, payload: MigrationPayload, transport: MigrationTransport) async {
        self.accountId = accountId
        var payload = payload
        payload.recipes = payload.recipes.filter { MigrationSelection.includesRecipe(origin: $0.origin) }
        record = LocalMigrationStore(defaults: defaults).load(accountId: accountId)
        guard record.phase != .done else { return }
        record = LocalMigrationMachine.start(record)
        persist()
        do {
            let uploaded = try await transport.upload(payload)
            record = LocalMigrationMachine.uploaded(record, counts: uploaded)
            persist()
            let confirmed = try await transport.confirm()
            record = LocalMigrationMachine.verified(record, counts: confirmed)
            persist()
            Analytics.track(.migrationDone)
        } catch {
            record = LocalMigrationMachine.failed(
                record,
                message: "Aktarım yarım kaldı. Yeniden deneyebilirsin."
            )
            persist()
        }
    }

    private func persist() {
        guard !accountId.isEmpty else { return }
        LocalMigrationStore(defaults: defaults).save(accountId: accountId, record: record)
    }
}
