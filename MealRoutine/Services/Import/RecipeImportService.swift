import Foundation
import SwiftData

enum RecipeValidationService {
    static func validate(_ form: RecipeForm) -> RecipeValidationResult {
        var issues: [RecipeValidationIssue] = []
        if form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingName)
        }
        let active = form.ingredients.filter(isActiveIngredient)
        if active.isEmpty || active.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.missingIngredient)
        }
        if active.contains(where: { ($0.quantity ?? 0) <= 0 }) {
            issues.append(.missingQuantity)
        }
        let steps = form.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let filled = steps.filter { !$0.isEmpty }
        if filled.isEmpty {
            issues.append(.missingInstruction)
        } else if steps.contains(where: \.isEmpty) {
            issues.append(.emptyInstruction)
        }
        if (form.servings ?? 0) <= 0 {
            issues.append(.missingServings)
        }
        return issues.isEmpty ? .valid : .invalid(issues)
    }

    /// Visual order: name, servings, each ingredient, then each step. The editor focuses the first.
    static func invalidFields(in form: RecipeForm) -> [RecipeEditorField] {
        var fields: [RecipeEditorField] = []
        if form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.name)
        }
        if (form.servings ?? 0) <= 0 {
            fields.append(.servings)
        }
        let active = form.ingredients.filter(isActiveIngredient)
        if active.isEmpty {
            if form.ingredients.indices.contains(0) {
                fields.append(.ingredientName(0))
            }
        } else {
            for (index, line) in form.ingredients.enumerated() where isActiveIngredient(line) {
                if line.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fields.append(.ingredientName(index))
                }
                if (line.quantity ?? 0) <= 0 {
                    fields.append(.ingredientQuantity(index))
                }
            }
        }
        let steps = form.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let filled = steps.contains { !$0.isEmpty }
        if !filled {
            if steps.indices.contains(0) {
                fields.append(.step(0))
            }
        } else {
            for (index, step) in steps.enumerated() where step.isEmpty {
                fields.append(.step(index))
            }
        }
        return fields
    }

    static func message(for field: RecipeEditorField, in form: RecipeForm) -> String {
        switch field {
        case .name:
            RecipeValidationIssue.missingName.message
        case .servings:
            RecipeValidationIssue.missingServings.message
        case .ingredientName:
            RecipeValidationIssue.missingIngredient.message
        case .ingredientQuantity:
            RecipeValidationIssue.missingQuantity.message
        case .step:
            let hasText = form.steps.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return hasText
                ? RecipeValidationIssue.emptyInstruction.message
                : RecipeValidationIssue.missingInstruction.message
        }
    }

    static func validate(_ recipe: Recipe) -> RecipeValidationResult {
        validate(form(from: recipe))
    }

    /// Reads stored fields only. Kept off the main-actor collection service so planning can call it.
    static func form(from recipe: Recipe) -> RecipeForm {
        let ingredients = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { line in
                RecipeFormIngredient(
                    name: line.displayName,
                    quantity: line.quantity,
                    unit: line.unit,
                    preparationNote: line.displayNote,
                    isOptional: line.isOptional
                )
            }
        let steps = recipe.steps
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.displayText)
        let unknownTime = recipe.timeIsUnknown
        return RecipeForm(
            name: recipe.displayName,
            servings: recipe.baseServings > 0 ? recipe.baseServings : nil,
            prepMinutes: unknownTime ? nil : positiveMinutes(recipe.prepMinutes),
            cookMinutes: unknownTime ? nil : positiveMinutes(recipe.cookMinutes),
            totalMinutes: unknownTime ? nil : positiveMinutes(recipe.totalMinutes),
            category: recipe.category,
            cuisine: recipe.country,
            difficulty: recipe.difficulty == "unknown" ? "" : recipe.difficulty,
            notes: recipe.userNotes,
            ingredients: ingredients.isEmpty ? [RecipeFormIngredient()] : ingredients,
            steps: steps.isEmpty ? [""] : steps,
            sourceURL: recipe.sourceURL,
            sourceTitle: recipe.sourceTitle,
            sourcePlatform: recipe.sourcePlatform ?? .unknown,
            sourceImagePath: recipe.sourceImagePath,
            origin: recipe.origin == .builtIn ? .manual : recipe.origin
        )
    }

    private static func positiveMinutes(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    private static func isActiveIngredient(_ line: RecipeFormIngredient) -> Bool {
        if !line.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if line.quantity != nil { return true }
        if !line.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !line.preparationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
}

enum RecipeCollectionError: LocalizedError, Equatable {
    case duplicateSource(slug: String)
    case incomplete([RecipeValidationIssue])

    var errorDescription: String? {
        switch self {
        case .duplicateSource:
            "Bu kaynak zaten kayıtlı."
        case .incomplete(let issues):
            issues.map(\.message).joined(separator: "\n")
        }
    }
}

/// Quick Save, completion, deletion, and URL duplicates. It does not read web pages.
@MainActor
enum RecipeCollectionService {
    @discardableResult
    static func quickSave(
        _ capture: RecipeCapture,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Recipe {
        if !capture.allowDuplicate, let existing = try duplicate(of: capture, in: context) {
            Analytics.track(.savedRecipeDuplicateDetected, properties: sourceProperties(existing))
            return existing
        }
        let recipe = makeShell(slug: freshSlug(), now: now)
        fillQuickSave(recipe, capture: capture, now: now)
        context.insert(recipe)
        try context.save()
        CatalogIndexCache.invalidate()
        try? refreshIndex(in: context)
        Analytics.track(.recipeQuickSaved, properties: sourceProperties(recipe))
        return recipe
    }

    static func duplicate(of capture: RecipeCapture, in context: ModelContext) throws -> Recipe? {
        guard let raw = capture.urlString else { return nil }
        return try duplicateSlug(for: raw, in: context).flatMap { slug in
            try context.fetch(FetchDescriptor<Recipe>()).first { $0.slug == slug }
        }
    }

    static func duplicateSlug(
        for rawURL: String,
        in context: ModelContext,
        excluding slug: String? = nil
    ) throws -> String? {
        guard let key = RecipeSourceService.normalizedKey(rawURL) else { return nil }
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        return recipes.first { recipe in
            recipe.slug != slug
                && !recipe.isBundledCatalog
                && RecipeSourceService.normalizedKey(recipe.sourceURL) == key
        }?.slug
    }

    /// Saves a completed personal recipe. Refuses a second copy of the same source URL
    /// unless `allowDuplicate` is set. Never overwrites a different recipe.
    @discardableResult
    static func save(
        _ form: RecipeForm,
        slug: String?,
        allowDuplicate: Bool = false,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Recipe {
        let result = RecipeValidationService.validate(form)
        guard case .valid = result else {
            throw RecipeCollectionError.incomplete(result.issues)
        }
        if !allowDuplicate, let existing = try duplicateSlug(for: form.sourceURL, in: context, excluding: slug) {
            Analytics.track(.savedRecipeDuplicateDetected, properties: [
                "origin": form.origin.rawValue,
                "platform": form.sourcePlatform.rawValue,
                "state": RecipeCollectionState.readyToCook.rawValue,
            ])
            throw RecipeCollectionError.duplicateSource(slug: existing)
        }
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let existing = slug.flatMap { key in recipes.first { $0.slug == key && !$0.isBundledCatalog } }
        let created = existing == nil
        let recipe = existing ?? makeShell(slug: freshSlug(), now: now)
        let wasSavedToTry = existing?.collectionState == .savedToTry
        if created {
            context.insert(recipe)
            recipe.origin = form.origin == .builtIn ? .manual : form.origin
            recipe.savedAt = now
        }
        fillCompleted(recipe, form: form, now: now, keepSavedAt: existing?.savedAt)
        replaceIngredients(of: recipe, with: form, in: context)
        replaceSteps(of: recipe, with: form, in: context)
        if wasSavedToTry || created {
            recipe.completedAt = now
        }
        try context.save()
        CatalogIndexCache.invalidate()
        try? refreshIndex(in: context)
        if created && recipe.origin == .manual {
            Analytics.track(.recipeAddedManually, properties: sourceProperties(recipe))
        }
        if wasSavedToTry || (created && recipe.origin == .savedExternal) {
            Analytics.track(.recipeCompletionFinished, properties: sourceProperties(recipe))
        }
        return recipe
    }

    static func delete(_ recipe: Recipe, in context: ModelContext) throws {
        guard !recipe.isBundledCatalog else { return }
        let properties = sourceProperties(recipe)
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
        try? refreshIndex(in: context)
        Analytics.track(.savedRecipeDeleted, properties: properties)
    }

    /// Materializes captures the share extension already wrote. Does not overwrite a saved recipe.
    @discardableResult
    static func drainCaptures(in context: ModelContext, now: Date = .now) throws -> [UUID: String] {
        let pending = RecipeCaptureStore.pending()
        guard !pending.isEmpty else { return [:] }
        var mapped: [UUID: String] = [:]
        for capture in pending {
            let recipe = try quickSave(capture, in: context, now: capture.capturedAt)
            mapped[capture.id] = recipe.slug
            RecipeCaptureStore.remove(ids: [capture.id])
        }
        try? refreshIndex(in: context)
        return mapped
    }

    static func form(from recipe: Recipe) -> RecipeForm {
        RecipeValidationService.form(from: recipe)
    }

    static func refreshIndex(in context: ModelContext) throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let records = recipes.compactMap { recipe -> CollectionSourceRecord? in
            guard !recipe.isBundledCatalog,
                  let key = RecipeSourceService.normalizedKey(recipe.sourceURL) else { return nil }
            return CollectionSourceRecord(
                slug: recipe.slug,
                title: recipe.displayName,
                normalizedURL: key,
                savedAt: recipe.savedAt ?? .now
            )
        }
        try RecipeCaptureStore.writeIndex(records)
    }

    private static func fillQuickSave(_ recipe: Recipe, capture: RecipeCapture, now: Date) {
        let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = capture.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = title.isEmpty ? fallbackTitle(from: text) : title
        recipe.nameTR = name
        recipe.origin = .savedExternal
        recipe.collectionState = .savedToTry
        recipe.sourceURL = capture.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recipe.sourceTitle = title
        recipe.sourcePlatform = capture.sourcePlatform
        recipe.sourceImagePath = capture.imagePath ?? ""
        recipe.savedAt = capture.capturedAt
        recipe.userNotes = text == name ? "" : text
        recipe.timeIsUnknown = true
        recipe.baseServings = 1
        recipe.difficulty = "unknown"
        recipe.sourceProvider = "saved"
        recipe.sourceAttribution = attribution(
            platform: capture.sourcePlatform,
            sourceTitle: title,
            url: recipe.sourceURL
        )
        recipe.importedAt = now
    }

    private static func fillCompleted(_ recipe: Recipe, form: RecipeForm, now: Date, keepSavedAt: Date?) {
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.nameTR = name
        recipe.collectionState = .readyToCook
        recipe.userNotes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summaryTR = recipe.userNotes
        recipe.category = form.category.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.country = form.cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        let difficulty = form.difficulty.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.difficulty = difficulty.isEmpty ? "unknown" : difficulty
        recipe.baseServings = form.servings ?? 1
        recipe.prepMinutes = form.prepMinutes ?? 0
        recipe.cookMinutes = form.cookMinutes ?? 0
        if let total = form.totalMinutes {
            recipe.totalMinutes = total
            recipe.timeIsUnknown = false
        } else if form.prepMinutes != nil || form.cookMinutes != nil {
            recipe.totalMinutes = (form.prepMinutes ?? 0) + (form.cookMinutes ?? 0)
            recipe.timeIsUnknown = false
        } else {
            recipe.totalMinutes = 0
            recipe.timeIsUnknown = true
        }
        recipe.sourceURL = form.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.sourceTitle = form.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.sourcePlatform = form.sourcePlatform
        recipe.sourceImagePath = form.sourceImagePath
        recipe.savedAt = keepSavedAt ?? recipe.savedAt ?? now
        recipe.origin = form.origin == .builtIn ? .manual : form.origin
        recipe.sourceProvider = recipe.origin == .manual ? "manual" : "saved"
        recipe.sourceAttribution = attribution(
            platform: form.sourcePlatform,
            sourceTitle: recipe.sourceTitle,
            url: recipe.sourceURL
        )
        recipe.servingsUnspecified = false
        recipe.confirmedMissingIngredients = false
        recipe.confirmedMissingInstructions = false
        if recipe.importedAt == nil { recipe.importedAt = now }
    }

    private static func replaceIngredients(of recipe: Recipe, with form: RecipeForm, in context: ModelContext) {
        for line in recipe.ingredients {
            context.delete(line)
        }
        recipe.ingredients = []
        let active = form.ingredients.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for (index, line) in active.enumerated() {
            let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let row = IngredientLine(
                ingredientId: ImportedIngredientIdentity.id(name: name),
                nameEN: "",
                nameTR: name,
                quantity: line.quantity,
                unit: line.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                scaling: "linear",
                note: line.preparationNote.trimmingCharacters(in: .whitespacesAndNewlines),
                noteTR: line.preparationNote.trimmingCharacters(in: .whitespacesAndNewlines),
                trAliasCurated: false,
                sortIndex: index
            )
            row.isOptional = line.isOptional
            row.includeInGrocery = line.quantity != nil
            row.recipe = recipe
            context.insert(row)
            recipe.ingredients.append(row)
        }
    }

    private static func replaceSteps(of recipe: Recipe, with form: RecipeForm, in context: ModelContext) {
        for step in recipe.steps {
            context.delete(step)
        }
        recipe.steps = []
        let texts = form.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for (index, text) in texts.enumerated() {
            let step = RecipeStep(textEN: "", textTR: text, minutes: nil, sortIndex: index)
            step.recipe = recipe
            context.insert(step)
            recipe.steps.append(step)
        }
    }

    private static func makeShell(slug: String, now: Date) -> Recipe {
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
            sourceProvider: "saved",
            sourceLicense: "",
            sourceAttribution: "",
            photoURL: "",
            photoAuthor: "",
            photoLicense: ""
        )
        recipe.savedAt = now
        recipe.timeIsUnknown = true
        recipe.collectionState = .savedToTry
        return recipe
    }

    private static func attribution(platform: RecipeSourcePlatform, sourceTitle: String, url: String) -> String {
        let name = RecipeSourceService.displayName(platform: platform, sourceTitle: sourceTitle, url: url)
        if name.isEmpty || name == RecipeSourcePlatform.unknown.title { return "Kaynak: dış tarif" }
        return "Kaynak: \(name)"
    }

    private static func fallbackTitle(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Kaydedilen tarif" }
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }

    private static func freshSlug() -> String {
        "kayit-\(UUID().uuidString.lowercased())"
    }

    private static func sourceProperties(_ recipe: Recipe) -> [String: String] {
        [
            "origin": recipe.origin.rawValue,
            "platform": recipe.sourcePlatform?.rawValue ?? RecipeSourcePlatform.unknown.rawValue,
            "state": recipe.collectionState.rawValue,
        ]
    }
}

enum ImportedIngredientIdentity {
    static func id(name: String) -> String {
        let folded = UnitNormalization.fold(name)
        return "import:\(folded.isEmpty ? "line" : folded)"
    }
}

enum ImportedRecipeEligibility {
    /// Catalog rows stay plannable. A personal recipe must be ready to cook and pass validation.
    /// Not main-actor isolated: the week index calls this while it is building candidates.
    nonisolated static func allowsPlanning(_ recipe: Recipe) -> Bool {
        if recipe.isBundledCatalog { return true }
        guard recipe.collectionState == .readyToCook else { return false }
        return RecipeValidationService.validate(recipe) == .valid
    }
}

enum ImportedGrocery {
    /// One shopping row. A line without a quantity stays off the list.
    /// Optional lines keep a separate id so they are not added to a required amount.
    static func sourceLine(for ingredient: IngredientLine) -> GrocerySourceLine? {
        guard ingredient.includeInGrocery else { return nil }
        let name = ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let personal = ingredient.recipe.map { !$0.isBundledCatalog } ?? false
        if personal && ingredient.quantity == nil { return nil }
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

enum RecipeCollectionLabels {
    static func badges(for recipe: Recipe) -> [String] {
        guard !recipe.isBundledCatalog else { return [] }
        var labels = [recipe.collectionState.title]
        switch recipe.origin {
        case .manual:
            labels.append("Elle yazıldı")
        case .savedExternal:
            if let platform = recipe.sourcePlatform {
                labels.append(platform.title)
            }
        case .builtIn:
            break
        }
        return labels
    }
}
