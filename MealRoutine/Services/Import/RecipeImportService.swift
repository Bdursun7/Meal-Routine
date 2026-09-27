import Foundation
import SwiftData

struct ImportSaveDecision: Equatable, Sendable {
    var canSave: Bool
    var blockers: [ImportWarning]
}

enum RecipeDuplicateService {
    static func matches(
        for document: RecipeImportDocument,
        among recipes: [RecipeDuplicateInput],
        excludingSlug: String? = nil
    ) -> [DuplicateCandidate] {
        let source = URLNormalizer.normalizedString(document.sourceURL) ?? ""
        let sourceKey = document.sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedTitle(document.title)
        let ingredients = Set(document.ingredients.map { normalizedTitle($0.name) }.filter { !$0.isEmpty })
        var found: [DuplicateCandidate] = []
        for recipe in recipes {
            if let excludingSlug, recipe.slug == excludingSlug { continue }
            let recipeURL = URLNormalizer.normalizedString(recipe.sourceURL) ?? ""
            let recipeKey = recipe.sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty, source == recipeURL {
                found.append(DuplicateCandidate(
                    slug: recipe.slug,
                    title: recipe.title,
                    strength: .strong,
                    reason: "Aynı kaynak adresi zaten kayıtlı.",
                    isUserEdited: recipe.isUserEdited
                ))
                continue
            }
            if !sourceKey.isEmpty, sourceKey == recipeKey {
                found.append(DuplicateCandidate(
                    slug: recipe.slug,
                    title: recipe.title,
                    strength: .strong,
                    reason: "Aynı kaynak kaydı zaten koleksiyonda.",
                    isUserEdited: recipe.isUserEdited
                ))
                continue
            }
            let otherTitle = normalizedTitle(recipe.title)
            guard !title.isEmpty, !otherTitle.isEmpty else { continue }
            let titleScore = similarity(title, otherTitle)
            let otherIngredients = Set(recipe.ingredientNames.map(normalizedTitle).filter { !$0.isEmpty })
            let ingredientScore = jaccard(ingredients, otherIngredients)
            let titlesMatch = title == otherTitle && title.count >= 8
            let titlesClose = titleScore >= 0.85
            let ingredientsClose = ingredients.count >= 2 && otherIngredients.count >= 2 && ingredientScore >= 0.55
            let sameSourceTitle = !source.isEmpty && !recipeURL.isEmpty && sourceHost(source) == sourceHost(recipeURL) && titlesMatch
            if titlesMatch || (titlesClose && ingredientsClose) || sameSourceTitle {
                found.append(DuplicateCandidate(
                    slug: recipe.slug,
                    title: recipe.title,
                    strength: .medium,
                    reason: "Başlık ve malzemeler mevcut bir tarife çok benziyor.",
                    isUserEdited: recipe.isUserEdited
                ))
            }
        }
        return found.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength == .strong }
            return lhs.slug < rhs.slug
        }
    }

    static func changes(from current: RecipeImportDocument, to incoming: RecipeImportDocument) -> [ReimportFieldChange] {
        var items: [ReimportFieldChange] = []
        func add(_ field: ReimportField, _ left: String, _ right: String) {
            let currentText = left.trimmingCharacters(in: .whitespacesAndNewlines)
            let incomingText = right.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentText != incomingText else { return }
            items.append(ReimportFieldChange(field: field, currentText: currentText, incomingText: incomingText))
        }
        add(.title, current.title, incoming.title)
        add(.summary, current.summary, incoming.summary)
        add(.category, current.category, incoming.category)
        add(.cuisine, current.cuisine, incoming.cuisine)
        add(.time, timeText(current), timeText(incoming))
        add(.servings, current.servings.map(String.init) ?? "", incoming.servings.map(String.init) ?? "")
        add(.difficulty, current.difficulty, incoming.difficulty)
        add(.ingredients, ingredientText(current), ingredientText(incoming))
        add(.instructions, instructionText(current), instructionText(incoming))
        add(.source, sourceText(current), sourceText(incoming))
        add(.notes, current.notes, incoming.notes)
        return items
    }

    static func normalizedTitle(_ raw: String) -> String {
        UnitNormalization.fold(raw)
    }

    private static func timeText(_ document: RecipeImportDocument) -> String {
        [document.prepMinutes, document.cookMinutes, document.totalMinutes]
            .map { $0.map(String.init) ?? "" }
            .joined(separator: "/")
    }

    private static func ingredientText(_ document: RecipeImportDocument) -> String {
        document.ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.originalText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func instructionText(_ document: RecipeImportDocument) -> String {
        document.instructions
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func sourceText(_ document: RecipeImportDocument) -> String {
        [document.sourceURL, document.sourceTitle, document.sourcePlatform.rawValue].joined(separator: "|")
    }

    private static func sourceHost(_ normalized: String) -> String {
        URL(string: normalized)?.host ?? ""
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        let left = Set(lhs.split(separator: " ").map(String.init))
        let right = Set(rhs.split(separator: " ").map(String.init))
        let tokenScore = jaccard(left, right)
        if lhs.count >= 8, rhs.count >= 8, lhs.contains(rhs) || rhs.contains(lhs) {
            return max(tokenScore, 0.9)
        }
        return tokenScore
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }
}

enum ImportedIngredientIdentity {
    static func id(name: String) -> String {
        let folded = UnitNormalization.fold(name)
        return "import:\(folded.isEmpty ? "line" : folded)"
    }
}

enum ImportedRecipeEligibility {
    /// Built-in recipes stay on the existing planner path.
    /// A saved import needs a title plus ingredients and steps, or an explicit confirmation that those are missing.
    static func allowsPlanning(_ recipe: Recipe) -> Bool {
        if recipe.isBundledCatalog { return true }
        guard recipe.importStatus == .ready, !recipe.requiresReview else { return false }
        guard !recipe.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let named = recipe.ingredients.contains {
            !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !named && !recipe.confirmedMissingIngredients { return false }
        let steps = recipe.steps.contains {
            !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !steps && !recipe.confirmedMissingInstructions { return false }
        return true
    }
}

enum ImportedGrocery {
    /// One shopping row. Unstructured lines are omitted until `includeInGrocery` is on.
    /// Optional lines keep a separate id so they are not added to a required amount.
    static func sourceLine(for ingredient: IngredientLine) -> GrocerySourceLine? {
        guard ingredient.includeInGrocery else { return nil }
        let name = ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let id = ingredient.isOptional ? "\(ingredient.ingredientId)|optional" : ingredient.ingredientId
        let display = ingredient.isOptional ? "\(name) (isteğe bağlı)" : name
        return GrocerySourceLine(
            ingredientId: id,
            nameTR: display,
            nameEN: ingredient.nameEN,
            quantity: ingredient.quantity,
            unit: ingredient.unit
        )
    }
}

enum RecipeImportLabels {
    static func badges(for recipe: Recipe, cooked: Bool, isFavorite: Bool) -> [String] {
        guard !recipe.isBundledCatalog else { return [] }
        var labels: [String] = []
        switch recipe.origin {
        case .builtIn:
            break
        case .imported:
            labels.append("İçe aktarıldı")
        case .manual:
            labels.append("Elle girildi")
        }
        if recipe.requiresReview || recipe.importStatus == .needsReview {
            labels.append("İnceleme bekliyor")
        }
        if !cooked && !isFavorite && recipe.importStatus == .ready {
            labels.append("Koleksiyonunda yeni")
        }
        if recipe.isUserEdited {
            labels.append("Sen düzenledin")
        }
        return labels
    }
}

struct ImportSaveResult: Equatable, Sendable {
    var slug: String
    var created: Bool
}

/// Review, drafts, and the save that turns a document into a normal recipe.
@MainActor
enum RecipeImportService {
    static func saveDecision(_ document: RecipeImportDocument) -> ImportSaveDecision {
        var blockers: [ImportWarning] = []
        if document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blockers.append(.missingTitle)
        }
        let named = document.ingredients.contains {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !named && !document.confirmedMissingIngredients {
            blockers.append(.missingIngredients)
        }
        let steps = document.instructions.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !steps && !document.confirmedMissingInstructions {
            blockers.append(.missingInstructions)
        }
        return ImportSaveDecision(canSave: blockers.isEmpty, blockers: blockers)
    }

    static func duplicateInputs(from recipes: [Recipe]) -> [RecipeDuplicateInput] {
        recipes.map { recipe in
            RecipeDuplicateInput(
                slug: recipe.slug,
                title: recipe.displayName,
                sourceURL: recipe.sourceURL,
                sourceKey: recipe.sourceKey,
                ingredientNames: recipe.ingredients.map(\.displayName),
                isUserEdited: recipe.isUserEdited,
                origin: recipe.origin
            )
        }
    }

    static func document(from recipe: Recipe) -> RecipeImportDocument {
        var document = RecipeImportDocument.emptyManual()
        document.title = recipe.displayName
        document.summary = recipe.displaySummary
        document.category = recipe.category
        document.cuisine = recipe.country
        document.prepMinutes = recipe.prepMinutes > 0 ? recipe.prepMinutes : nil
        document.cookMinutes = recipe.cookMinutes > 0 ? recipe.cookMinutes : nil
        document.totalMinutes = recipe.timeIsUnknown ? nil : (recipe.totalMinutes > 0 ? recipe.totalMinutes : nil)
        document.servings = recipe.servingsUnspecified ? nil : (recipe.baseServings > 0 ? recipe.baseServings : nil)
        document.difficulty = recipe.difficulty.isEmpty ? "unknown" : recipe.difficulty
        document.ingredients = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { line in
                ImportedIngredient(
                    name: line.displayName,
                    quantity: line.quantity,
                    unit: line.unit.isEmpty ? nil : line.unit,
                    preparationNote: line.displayNote.isEmpty ? nil : line.displayNote,
                    isOptional: line.isOptional,
                    isUncertain: line.isUncertain,
                    originalText: line.originalText.isEmpty ? line.displayName : line.originalText,
                    sortOrder: line.sortIndex,
                    includeInGrocery: line.includeInGrocery
                )
            }
        document.instructions = recipe.steps
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { step in
                ImportedInstruction(
                    text: step.displayText,
                    sortOrder: step.sortIndex,
                    isUncertain: step.isUncertain,
                    originalText: step.originalText.isEmpty ? step.displayText : step.originalText
                )
            }
        document.sourceURL = recipe.sourceURL
        document.sourceTitle = recipe.sourceTitle
        document.sourcePlatform = recipe.sourcePlatform ?? .unknown
        document.sourceKey = recipe.sourceKey
        document.extractionConfidence = recipe.extractionConfidence
        document.origin = recipe.origin == .builtIn ? .imported : recipe.origin
        document.isUserEdited = recipe.isUserEdited
        document.notes = recipe.userNotes
        document.confirmedMissingIngredients = recipe.confirmedMissingIngredients
        document.confirmedMissingInstructions = recipe.confirmedMissingInstructions
        return document
    }

    @discardableResult
    static func save(
        _ document: RecipeImportDocument,
        replacing slug: String? = nil,
        recordEdit: Bool = false,
        in context: ModelContext,
        now: Date = .now
    ) throws -> ImportSaveResult {
        let decision = saveDecision(document)
        guard decision.canSave else {
            throw ImportSaveError.incomplete(decision.blockers)
        }
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let existing = slug.flatMap { key in recipes.first { $0.slug == key } }
        let created = existing == nil
        let recipe = existing ?? makeRecipe(slug: freshSlug(), document: document, now: now)
        if created {
            context.insert(recipe)
        }
        fill(recipe, with: document, now: now, keepImportedAt: existing?.importedAt)
        replaceChildren(of: recipe, with: document, in: context)
        if created {
            try BehaviorTrackingService.record(.imported, recipeSlug: recipe.slug, at: now, in: context, saves: false)
        } else if recordEdit {
            try BehaviorTrackingService.record(.edited, recipeSlug: recipe.slug, at: now, in: context, saves: false)
        }
        try stampSnapshots(for: recipe, in: context)
        try context.save()
        CatalogIndexCache.invalidate()
        Analytics.track(.importSaved, properties: [
            "origin": document.origin.rawValue,
            "platform": document.sourcePlatform.rawValue,
        ])
        return ImportSaveResult(slug: recipe.slug, created: created)
    }

    static func saveDraft(
        _ document: RecipeImportDocument,
        state: RecipeDraftState,
        existing: RecipeImportDraft? = nil,
        linkedSlug: String = "",
        errorMessage: String = "",
        in context: ModelContext,
        now: Date = .now
    ) throws -> RecipeImportDraft {
        let draft = existing ?? RecipeImportDraft(
            status: state,
            origin: document.origin,
            createdAt: now
        )
        if existing == nil {
            context.insert(draft)
        }
        draft.state = state
        draft.origin = document.origin
        draft.sourceURL = document.sourceURL
        draft.title = document.title
        draft.payloadJSON = try encode(document)
        draft.errorMessage = errorMessage
        draft.updatedAt = now
        draft.linkedRecipeSlug = linkedSlug
        try context.save()
        Analytics.track(.importDraftSaved, properties: ["state": state.rawValue])
        return draft
    }

    static func document(from draft: RecipeImportDraft) -> RecipeImportDocument? {
        guard let data = draft.payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecipeImportDocument.self, from: data)
    }

    static func delete(_ recipe: Recipe, in context: ModelContext) throws {
        guard !recipe.isBundledCatalog else { return }
        let slug = recipe.slug
        let title = recipe.displayName
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let current = try WeekPlanService.currentWeek(in: context)
        for meal in meals where meal.recipeSlug == slug {
            if meal.titleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meal.titleSnapshot = title
            }
            let isCurrent = meal.week?.uuid == current?.uuid
            if isCurrent && meal.cookedAt == nil {
                context.delete(meal)
            }
        }
        context.delete(recipe)
        try context.save()
        CatalogIndexCache.invalidate()
        GroceryListService.discardRebuildCache()
        try GroceryListService.rebuild(in: context)
        Analytics.track(.importedRecipeDeleted, properties: ["origin": "imported"])
    }

    private static func encode(_ document: RecipeImportDocument) throws -> String {
        let data = try JSONEncoder().encode(document)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportSaveError.encoding
        }
        return text
    }

    private static func freshSlug() -> String {
        "imp-\(UUID().uuidString.lowercased())"
    }

    private static func makeRecipe(slug: String, document: RecipeImportDocument, now: Date) -> Recipe {
        let recipe = Recipe(
            slug: slug,
            nameEN: "",
            nameTR: "",
            nativeName: "",
            summaryEN: "",
            summaryTR: "",
            country: "",
            category: "",
            unitoolsCategory: "",
            diets: [],
            difficulty: "unknown",
            baseServings: 1,
            prepMinutes: 0,
            cookMinutes: 0,
            totalMinutes: 0,
            tags: [],
            trDogfoodScore: 0,
            hardIngredientPenalty: 0,
            calories: 0,
            protein: 0,
            fat: 0,
            carbs: 0,
            sourceProvider: document.origin == .manual ? "manual" : "import",
            sourceLicense: "",
            sourceAttribution: "",
            photoURL: "",
            photoAuthor: "",
            photoLicense: ""
        )
        recipe.importedAt = now
        return recipe
    }

    private static func fill(_ recipe: Recipe, with document: RecipeImportDocument, now: Date, keepImportedAt: Date?) {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.nameTR = title
        recipe.nameEN = ""
        recipe.nativeName = ""
        recipe.summaryTR = document.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summaryEN = ""
        recipe.country = document.cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = document.category.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.category = category
        recipe.unitoolsCategory = category
        recipe.diets = []
        recipe.difficulty = document.difficulty.isEmpty ? "unknown" : document.difficulty
        recipe.servingsUnspecified = document.servings == nil
        recipe.baseServings = max(document.servings ?? 1, 1)
        recipe.prepMinutes = document.prepMinutes ?? 0
        recipe.cookMinutes = document.cookMinutes ?? 0
        recipe.totalMinutes = document.totalMinutes ?? 0
        recipe.timeIsUnknown = document.totalMinutes == nil
        recipe.tags = []
        recipe.trDogfoodScore = 0
        recipe.calories = 0
        recipe.protein = 0
        recipe.fat = 0
        recipe.carbs = 0
        recipe.sourceProvider = document.origin == .manual ? "manual" : "import"
        recipe.sourceLicense = ""
        recipe.sourceAttribution = attribution(for: document)
        recipe.photoURL = ""
        recipe.photoAuthor = ""
        recipe.photoLicense = ""
        recipe.origin = document.origin
        recipe.sourceURL = document.sourceURL
        recipe.sourceTitle = document.sourceTitle
        recipe.sourcePlatform = document.sourcePlatform
        recipe.sourceKey = document.sourceKey
        recipe.importedAt = keepImportedAt ?? recipe.importedAt ?? now
        recipe.lastImportedAt = now
        recipe.importStatus = .ready
        recipe.extractionConfidence = document.extractionConfidence
        recipe.requiresReview = false
        recipe.isUserEdited = document.isUserEdited
        recipe.userNotes = document.notes
        recipe.confirmedMissingIngredients = document.confirmedMissingIngredients
        recipe.confirmedMissingInstructions = document.confirmedMissingInstructions
    }

    private static func attribution(for document: RecipeImportDocument) -> String {
        var parts = ["Kaynak: \(document.sourcePlatform.title)"]
        let title = document.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.caseInsensitiveCompare(document.title) != .orderedSame {
            parts.append(title)
        }
        let url = document.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
            parts.append(url)
        }
        if document.origin == .manual, url.isEmpty {
            return "Elle girildi. MealRoutine bu tarifi yazmadı."
        }
        return parts.joined(separator: " · ")
    }

    private static func replaceChildren(of recipe: Recipe, with document: RecipeImportDocument, in context: ModelContext) {
        for line in recipe.ingredients {
            context.delete(line)
        }
        for step in recipe.steps {
            context.delete(step)
        }
        recipe.ingredients = []
        recipe.steps = []
        let scaling = document.servings == nil ? "fixed" : "linear"
        for ingredient in document.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let line = IngredientLine(
                ingredientId: ImportedIngredientIdentity.id(name: name),
                nameEN: "",
                nameTR: name,
                quantity: ingredient.quantity,
                unit: ingredient.unit ?? "",
                scaling: scaling,
                note: ingredient.preparationNote ?? "",
                noteTR: ingredient.preparationNote ?? "",
                trAliasCurated: false,
                sortIndex: ingredient.sortOrder
            )
            line.isOptional = ingredient.isOptional
            line.isUncertain = ingredient.isUncertain
            line.originalText = ingredient.originalText
            line.includeInGrocery = ingredient.includeInGrocery && !name.isEmpty
            context.insert(line)
            line.recipe = recipe
        }
        for step in document.instructions.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let model = RecipeStep(
                textEN: "",
                textTR: text,
                minutes: nil,
                sortIndex: step.sortOrder
            )
            model.isUncertain = step.isUncertain
            model.originalText = step.originalText
            context.insert(model)
            model.recipe = recipe
        }
    }

    private static func stampSnapshots(for recipe: Recipe, in context: ModelContext) throws {
        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        for meal in meals where meal.recipeSlug == recipe.slug {
            meal.titleSnapshot = recipe.displayName
        }
    }
}

enum ImportSaveError: Equatable, Error, LocalizedError {
    case incomplete([ImportWarning])
    case encoding

    var errorDescription: String? {
        switch self {
        case .incomplete(let warnings):
            warnings.first?.message ?? "Tarif kaydedilmeden önce eksikleri tamamla."
        case .encoding:
            "Taslak bu cihazda saklanamadı."
        }
    }
}
