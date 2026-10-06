import Foundation
import SwiftData

enum RecipeValidationService {
    static func validate(_ form: RecipeForm) -> RecipeValidationResult {
        var issues: [RecipeValidationIssue] = []
        if let issue = nameIssue(form.name) {
            issues.append(issue)
        }
        if let issue = servingsIssue(form) {
            issues.append(issue)
        }
        let active = form.ingredients.filter(isActiveIngredient)
        var missingIngredient = active.isEmpty
        var missingQuantity = false
        var invalidQuantity = false
        var quantityTooLong = false
        var missingUnit = false
        var ingredientNameTooLong = false
        var noteTooLong = false
        for line in active {
            if let issue = ingredientNameIssue(line.name) {
                switch issue {
                case .missingIngredient:
                    missingIngredient = true
                case .ingredientNameTooLong:
                    ingredientNameTooLong = true
                default:
                    break
                }
            }
            if let issue = quantityIssue(line) {
                switch issue {
                case .missingQuantity:
                    missingQuantity = true
                case .invalidQuantity:
                    invalidQuantity = true
                case .quantityTooLong:
                    quantityTooLong = true
                default:
                    break
                }
            }
            if !hasCatalogUnit(line) {
                missingUnit = true
            }
            if trimmed(line.preparationNote).count > RecipeFieldLimits.preparationNote {
                noteTooLong = true
            }
        }
        if missingIngredient { issues.append(.missingIngredient) }
        if invalidQuantity { issues.append(.invalidQuantity) }
        if quantityTooLong { issues.append(.quantityTooLong) }
        if missingQuantity { issues.append(.missingQuantity) }
        if missingUnit { issues.append(.missingUnit) }
        if ingredientNameTooLong { issues.append(.ingredientNameTooLong) }
        if noteTooLong { issues.append(.preparationNoteTooLong) }
        issues.append(contentsOf: stepIssues(form.steps))
        if let issue = minutesIssue(form.prepMinutesText) { issues.append(issue) }
        if let cook = minutesIssue(form.cookMinutesText), !issues.contains(cook) { issues.append(cook) }
        if let total = minutesIssue(form.totalMinutesText), !issues.contains(total) { issues.append(total) }
        if trimmed(form.category).count > RecipeFieldLimits.category { issues.append(.categoryTooLong) }
        if trimmed(form.cuisine).count > RecipeFieldLimits.cuisine { issues.append(.cuisineTooLong) }
        if trimmed(form.notes).count > RecipeFieldLimits.notes { issues.append(.notesTooLong) }
        if trimmed(form.sourceURL).count > RecipeFieldLimits.sourceURL { issues.append(.sourceURLTooLong) }
        if trimmed(form.sourceTitle).count > RecipeFieldLimits.sourceTitle { issues.append(.sourceTitleTooLong) }
        return issues.isEmpty ? .valid : .invalid(issues)
    }

    /// Visual order matches the form. The editor focuses the first field.
    static func invalidFields(in form: RecipeForm) -> [RecipeEditorField] {
        var fields: [RecipeEditorField] = []
        if nameIssue(form.name) != nil {
            fields.append(.name)
        }
        if servingsIssue(form) != nil {
            fields.append(.servings)
        }
        let active = form.ingredients.filter(isActiveIngredient)
        if active.isEmpty {
            if form.ingredients.indices.contains(0) {
                fields.append(.ingredientName(0))
            }
        } else {
            for (index, line) in form.ingredients.enumerated() where isActiveIngredient(line) {
                if ingredientNameIssue(line.name) != nil {
                    fields.append(.ingredientName(index))
                }
                if quantityIssue(line) != nil {
                    fields.append(.ingredientQuantity(index))
                }
                if !hasCatalogUnit(line) {
                    fields.append(.ingredientUnit(index))
                }
                if trimmed(line.preparationNote).count > RecipeFieldLimits.preparationNote {
                    fields.append(.ingredientNote(index))
                }
            }
        }
        let steps = form.steps.map(trimmed)
        let filled = steps.contains { !$0.isEmpty }
        if !filled {
            if steps.indices.contains(0) {
                fields.append(.step(0))
            }
        } else {
            for (index, step) in steps.enumerated() where step.isEmpty || step.count > RecipeFieldLimits.step {
                fields.append(.step(index))
            }
        }
        if minutesIssue(form.prepMinutesText) != nil { fields.append(.prepMinutes) }
        if minutesIssue(form.cookMinutesText) != nil { fields.append(.cookMinutes) }
        if minutesIssue(form.totalMinutesText) != nil { fields.append(.totalMinutes) }
        if trimmed(form.category).count > RecipeFieldLimits.category { fields.append(.category) }
        if trimmed(form.cuisine).count > RecipeFieldLimits.cuisine { fields.append(.cuisine) }
        if trimmed(form.notes).count > RecipeFieldLimits.notes { fields.append(.notes) }
        if trimmed(form.sourceURL).count > RecipeFieldLimits.sourceURL { fields.append(.sourceURL) }
        if trimmed(form.sourceTitle).count > RecipeFieldLimits.sourceTitle { fields.append(.sourceTitle) }
        return fields
    }

    static func message(for field: RecipeEditorField, in form: RecipeForm) -> String {
        switch field {
        case .name:
            return nameIssue(form.name)?.message ?? RecipeValidationIssue.missingName.message
        case .servings:
            return servingsIssue(form)?.message ?? RecipeValidationIssue.missingServings.message
        case .ingredientName(let index):
            let name = form.ingredients.indices.contains(index) ? form.ingredients[index].name : ""
            return ingredientNameIssue(name)?.message ?? RecipeValidationIssue.missingIngredient.message
        case .ingredientQuantity(let index):
            guard form.ingredients.indices.contains(index) else {
                return RecipeValidationIssue.missingQuantity.message
            }
            return quantityIssue(form.ingredients[index])?.message ?? RecipeValidationIssue.missingQuantity.message
        case .ingredientUnit:
            return RecipeValidationIssue.missingUnit.message
        case .ingredientNote:
            return RecipeValidationIssue.preparationNoteTooLong.message
        case .step(let index):
            let text = form.steps.indices.contains(index) ? trimmed(form.steps[index]) : ""
            if text.count > RecipeFieldLimits.step {
                return RecipeValidationIssue.stepTooLong.message
            }
            let hasText = form.steps.contains { !trimmed($0).isEmpty }
            return hasText
                ? RecipeValidationIssue.emptyInstruction.message
                : RecipeValidationIssue.missingInstruction.message
        case .prepMinutes:
            return minutesIssue(form.prepMinutesText)?.message ?? RecipeValidationIssue.invalidMinutes.message
        case .cookMinutes:
            return minutesIssue(form.cookMinutesText)?.message ?? RecipeValidationIssue.invalidMinutes.message
        case .totalMinutes:
            return minutesIssue(form.totalMinutesText)?.message ?? RecipeValidationIssue.invalidMinutes.message
        case .category:
            return RecipeValidationIssue.categoryTooLong.message
        case .cuisine:
            return RecipeValidationIssue.cuisineTooLong.message
        case .notes:
            return RecipeValidationIssue.notesTooLong.message
        case .sourceURL:
            return RecipeValidationIssue.sourceURLTooLong.message
        case .sourceTitle:
            return RecipeValidationIssue.sourceTitleTooLong.message
        }
    }

    /// Servings the cook actually entered. Junk text does not become 0 or nil success.
    static func resolvedServings(_ form: RecipeForm) -> Int? {
        switch RecipeNumericInput.whole(form.servingsText, maxDigits: RecipeFieldLimits.servingsDigits) {
        case .value(let number):
            return number
        case .empty:
            return form.servings
        case .notANumber, .tooManyDigits:
            return nil
        }
    }

    /// Minutes the cook entered. Empty and 0 stay unknown. Junk stays unknown and fails validation.
    static func resolvedMinutes(text: String, stored: Int?) -> Int? {
        switch RecipeNumericInput.whole(text, maxDigits: RecipeFieldLimits.minutesDigits) {
        case .value(let number):
            return number > 0 ? number : nil
        case .empty:
            guard let stored, stored > 0 else { return nil }
            return stored
        case .notANumber, .tooManyDigits:
            return nil
        }
    }

    static func resolvedQuantity(_ line: RecipeFormIngredient) -> Double? {
        switch RecipeNumericInput.decimal(line.quantityText) {
        case .value(let number):
            return number
        case .empty:
            return line.quantity
        case .notANumber, .tooLong:
            return nil
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
            servingsText: "",
            prepMinutes: unknownTime ? nil : positiveMinutes(recipe.prepMinutes),
            prepMinutesText: "",
            cookMinutes: unknownTime ? nil : positiveMinutes(recipe.cookMinutes),
            cookMinutesText: "",
            totalMinutes: unknownTime ? nil : positiveMinutes(recipe.totalMinutes),
            totalMinutesText: "",
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

    private static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isActiveIngredient(_ line: RecipeFormIngredient) -> Bool {
        if !trimmed(line.name).isEmpty { return true }
        if !trimmed(line.quantityText).isEmpty { return true }
        if line.quantity != nil { return true }
        if !trimmed(line.unit).isEmpty { return true }
        if !trimmed(line.preparationNote).isEmpty { return true }
        return false
    }

    private static func hasCatalogUnit(_ line: RecipeFormIngredient) -> Bool {
        let code = RecipeUnitChoices.canonical(line.unit)
        return RecipeUnitChoices.codes.contains(code)
    }

    private static func nameIssue(_ raw: String) -> RecipeValidationIssue? {
        let name = trimmed(raw)
        if name.isEmpty { return .missingName }
        if name.count > RecipeFieldLimits.name { return .nameTooLong }
        return nil
    }

    private static func ingredientNameIssue(_ raw: String) -> RecipeValidationIssue? {
        let name = trimmed(raw)
        if name.isEmpty { return .missingIngredient }
        if name.count > RecipeFieldLimits.ingredientName { return .ingredientNameTooLong }
        return nil
    }

    private static func servingsIssue(_ form: RecipeForm) -> RecipeValidationIssue? {
        switch RecipeNumericInput.whole(form.servingsText, maxDigits: RecipeFieldLimits.servingsDigits) {
        case .notANumber:
            return .invalidServings
        case .tooManyDigits:
            return .servingsTooLong
        case .value(let number):
            return number >= 1 ? nil : .missingServings
        case .empty:
            guard let servings = form.servings, servings >= 1 else { return .missingServings }
            if String(servings).count > RecipeFieldLimits.servingsDigits { return .servingsTooLong }
            return nil
        }
    }

    private static func minutesIssue(_ text: String) -> RecipeValidationIssue? {
        switch RecipeNumericInput.whole(text, maxDigits: RecipeFieldLimits.minutesDigits) {
        case .notANumber:
            return .invalidMinutes
        case .tooManyDigits:
            return .minutesTooLong
        case .empty, .value:
            return nil
        }
    }

    private static func quantityIssue(_ line: RecipeFormIngredient) -> RecipeValidationIssue? {
        switch RecipeNumericInput.decimal(line.quantityText) {
        case .notANumber:
            return .invalidQuantity
        case .tooLong:
            return .quantityTooLong
        case .value(let number):
            return number > 0 ? nil : .missingQuantity
        case .empty:
            guard let quantity = line.quantity, quantity > 0 else { return .missingQuantity }
            if !storedQuantityFits(quantity) { return .quantityTooLong }
            return nil
        }
    }

    private static func storedQuantityFits(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        let text = value.rounded() == value && abs(value) < 1_000_000_000
            ? String(Int(value))
            : String((value * 100).rounded() / 100)
        if case .value = RecipeNumericInput.decimal(text) { return true }
        return false
    }

    private static func stepIssues(_ steps: [String]) -> [RecipeValidationIssue] {
        let texts = steps.map(trimmed)
        let filled = texts.filter { !$0.isEmpty }
        if filled.isEmpty { return [.missingInstruction] }
        var issues: [RecipeValidationIssue] = []
        if texts.contains(where: \.isEmpty) { issues.append(.emptyInstruction) }
        if filled.contains(where: { $0.count > RecipeFieldLimits.step }) { issues.append(.stepTooLong) }
        return issues
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
        PersonalRecipeSync.enqueue(recipe, in: context)
        Analytics.track(.recipeQuickSaved, properties: sourceProperties(recipe))
        return recipe
    }

    static func duplicate(of capture: RecipeCapture, in context: ModelContext) throws -> Recipe? {
        let name = savedName(title: capture.title ?? "", text: capture.text ?? "")
        return try duplicateSlug(
            url: capture.urlString ?? "",
            title: name,
            in: context
        ).flatMap { slug in
            try context.fetch(FetchDescriptor<Recipe>()).first { $0.slug == slug }
        }
    }

    static func duplicateSlug(
        url rawURL: String,
        title: String,
        sourceKey: String = "",
        in context: ModelContext,
        excluding slug: String? = nil
    ) throws -> String? {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let candidates = recipes.map { recipe in
            RecipeIdentity.Candidate(
                slug: recipe.slug,
                title: recipe.displayName,
                sourceURL: recipe.sourceURL,
                sourceKey: recipe.sourceKey,
                isBundled: recipe.isBundledCatalog
            )
        }
        return RecipeIdentity.duplicateSlug(
            url: rawURL,
            title: title,
            sourceKey: sourceKey,
            among: candidates,
            excluding: slug
        )
    }

    /// Saves a completed personal recipe. Refuses another personal recipe with the same
    /// normalized URL, source key, or near-identical title unless `allowDuplicate` is set.
    /// Never overwrites a different recipe.
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
        if !allowDuplicate, let existing = try duplicateSlug(
            url: form.sourceURL,
            title: form.name,
            sourceKey: "",
            in: context,
            excluding: slug
        ) {
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
        PersonalRecipeSync.enqueue(recipe, in: context)
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
            guard !recipe.isBundledCatalog else { return nil }
            let key = RecipeSourceService.normalizedKey(recipe.sourceURL) ?? ""
            let title = recipe.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty && !RecipeIdentity.titlesMatch(title, title) { return nil }
            return CollectionSourceRecord(
                slug: recipe.slug,
                title: title,
                normalizedURL: key,
                savedAt: recipe.savedAt ?? .now
            )
        }
        try RecipeCaptureStore.writeIndex(records)
    }

    private static func fillQuickSave(_ recipe: Recipe, capture: RecipeCapture, now: Date) {
        let title = RecipeTextLimit.clamp(
            capture.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxCharacters: RecipeFieldLimits.name
        )
        let text = RecipeTextLimit.clamp(
            capture.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxCharacters: RecipeFieldLimits.notes
        )
        let name = savedName(title: title, text: text)
        recipe.nameTR = name
        recipe.origin = .savedExternal
        recipe.collectionState = .savedToTry
        recipe.sourceURL = RecipeTextLimit.clamp(
            capture.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxCharacters: RecipeFieldLimits.sourceURL
        )
        recipe.sourceTitle = RecipeTextLimit.clamp(title, maxCharacters: RecipeFieldLimits.sourceTitle)
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
        recipe.baseServings = RecipeValidationService.resolvedServings(form) ?? 1
        let prep = RecipeValidationService.resolvedMinutes(text: form.prepMinutesText, stored: form.prepMinutes)
        let cook = RecipeValidationService.resolvedMinutes(text: form.cookMinutesText, stored: form.cookMinutes)
        let total = RecipeValidationService.resolvedMinutes(text: form.totalMinutesText, stored: form.totalMinutes)
        recipe.prepMinutes = prep ?? 0
        recipe.cookMinutes = cook ?? 0
        if let total {
            recipe.totalMinutes = total
            recipe.timeIsUnknown = false
        } else if prep != nil || cook != nil {
            recipe.totalMinutes = (prep ?? 0) + (cook ?? 0)
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
            let quantity = RecipeValidationService.resolvedQuantity(line)
            let row = IngredientLine(
                ingredientId: ImportedIngredientIdentity.id(name: name),
                nameEN: "",
                nameTR: name,
                quantity: quantity,
                unit: RecipeUnitChoices.canonical(line.unit),
                scaling: "linear",
                note: line.preparationNote.trimmingCharacters(in: .whitespacesAndNewlines),
                noteTR: line.preparationNote.trimmingCharacters(in: .whitespacesAndNewlines),
                trAliasCurated: false,
                sortIndex: index
            )
            row.isOptional = line.isOptional
            row.includeInGrocery = quantity != nil
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

    private static func savedName(title: String, text: String) -> String {
        let clampedTitle = RecipeTextLimit.clamp(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: RecipeFieldLimits.name
        )
        if !clampedTitle.isEmpty { return clampedTitle }
        let clampedText = RecipeTextLimit.clamp(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: RecipeFieldLimits.notes
        )
        return fallbackTitle(from: clampedText)
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

/// Personal recipes still waiting for ingredients and steps.
struct IncompleteRecipeSnapshot: Equatable, Sendable {
    var originRaw: String
    var collectionStateRaw: String
}

enum IncompleteRecipeQueue {
    static func isWaiting(_ row: IncompleteRecipeSnapshot) -> Bool {
        let origin = row.originRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if origin.isEmpty || origin == RecipeOrigin.builtIn.rawValue { return false }
        return row.collectionStateRaw == RecipeCollectionState.savedToTry.rawValue
    }

    static func count(_ rows: [IncompleteRecipeSnapshot]) -> Int {
        rows.reduce(0) { $0 + (isWaiting($1) ? 1 : 0) }
    }
}

/// Upserts one personal recipe through the shared pending-operation queue.
/// The board mutator never sees these items. Test mode and a signed-out device do not enqueue.
@MainActor
enum PersonalRecipeSync {
    static let entityType = "personalRecipe"
    static let operationType = "upsert"

    static func allows(testMode: Bool, signedIn: Bool, apiConfigured: Bool) -> Bool {
        !testMode && signedIn && apiConfigured
    }

    static func isPersonal(_ item: SyncWorkItem) -> Bool {
        item.entityType == entityType
    }

    static func enqueue(_ recipe: Recipe, in context: ModelContext) {
        guard allows(
            testMode: HouseholdTestMode.shared.isEnabled,
            signedIn: AuthSession.shared.account != nil,
            apiConfigured: MealRoutineConfig.apiBaseURL != nil
        ) else { return }
        guard AuthServices.sharedTokens.load()?.accessToken.isEmpty == false else { return }
        guard let item = workItem(for: recipe) else { return }
        let current = PendingOperationStore.items(in: context)
        PendingOperationStore.replace(merging(item, into: current), in: context)
        Task { await HouseholdSession.shared.drainPending(in: context) }
    }

    static func workItem(for recipe: Recipe, id: UUID = UUID(), now: Date = .now) -> SyncWorkItem? {
        guard MigrationSelection.includesRecipe(origin: recipe.originRaw) else { return nil }
        let payload = MigrationCollector.uploadPayload(for: recipe)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return SyncWorkItem(
            id: id,
            entityType: entityType,
            entityId: recipe.slug,
            operationType: operationType,
            payload: data,
            createdAt: now,
            retryCount: 0,
            status: .pending
        )
    }

    /// One pending upsert per slug. A newer save keeps the original idempotency id.
    static func merging(_ item: SyncWorkItem, into items: [SyncWorkItem]) -> [SyncWorkItem] {
        let prior = items.first { isPersonal($0) && $0.entityId == item.entityId }
        var stored = item
        if let prior {
            stored.id = prior.id
        }
        var next = items.filter { !(isPersonal($0) && $0.entityId == item.entityId) }
        next.append(stored)
        return next
    }

    static func send(_ items: [SyncWorkItem]) async -> [SyncWorkItem] {
        let personal = items.filter { isPersonal($0) }
        let others = items.filter { !isPersonal($0) }
        guard !personal.isEmpty else { return items }
        guard let baseURL = MealRoutineConfig.apiBaseURL,
              let token = AuthServices.sharedTokens.load()?.accessToken,
              !token.isEmpty,
              SyncEngine.shared.online else { return items }
        let client = MigrationHTTPClient(session: .shared, baseURL: baseURL, accessToken: token)
        let drained = await SyncDrainer.drain(items: personal, online: true, now: .now) { item in
            guard let payload = try? JSONDecoder().decode(MigrationPayload.self, from: item.payload) else {
                return .retry
            }
            do {
                _ = try await client.upload(payload)
                return .applied
            } catch {
                return .retry
            }
        }
        return others + drained
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
