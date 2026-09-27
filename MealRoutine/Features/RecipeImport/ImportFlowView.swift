import SwiftData
import SwiftUI

@MainActor
@Observable
final class ImportViewModel {
    enum Step: Equatable {
        case entry
        case extracting
        case review
        case failure(ImportFailure)
        case duplicate
        case reimport
    }

    var step: Step = .entry
    var document = RecipeImportDocument.emptyManual()
    var urlText = ""
    var pastedText = ""
    var errorMessage: String?
    var confirmSave = false
    var duplicate: DuplicateCandidate?
    var reimportChanges: [ReimportFieldChange] = []
    var selectedReimportFields: Set<ReimportField> = []
    var finishedSlug: String?
    private var extractTask: Task<Void, Never>?
    private var baseline: RecipeImportDocument?
    private var editsArmed = false
    private var replacingSlug: String?
    var draftID: UUID?
    private var sharedFallbackText: String?
    private var skipDuplicateCheck = false

    func prepare(editingSlug: String?, recipes: [Recipe], payload: SharedImportPayload?) {
        if let editingSlug, let recipe = recipes.first(where: { $0.slug == editingSlug }) {
            document = RecipeImportService.document(from: recipe)
            replacingSlug = recipe.slug
            armReview()
            step = .review
            Analytics.track(.importReviewOpened, properties: ["method": "edit"])
            return
        }
        if let payload {
            beginShare(payload)
        }
    }

    func startManual(keepingSource: Bool = false) {
        extractTask?.cancel()
        let sourceURL = document.sourceURL
        let sourceTitle = document.sourceTitle
        let sourcePlatform = document.sourcePlatform
        let sourceKey = document.sourceKey
        document = RecipeImportDocument.emptyManual()
        if keepingSource, !sourceURL.isEmpty {
            document.origin = .imported
            document.sourceURL = sourceURL
            document.sourceTitle = sourceTitle
            document.sourcePlatform = sourcePlatform
            document.sourceKey = sourceKey
        }
        replacingSlug = nil
        draftID = nil
        sharedFallbackText = nil
        skipDuplicateCheck = false
        armReview()
        step = .review
        Analytics.track(.importManualFallbackUsed, properties: ["method": "manual"])
        Analytics.track(.importReviewOpened, properties: ["method": "manual"])
    }

    func startURL() {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch URLNormalizer.classify(raw) {
        case .url(let url):
            beginExtraction(url: url, fallbackText: nil, hint: nil)
        case .unsupportedURL:
            step = .failure(.unsupportedSource)
        case .empty:
            step = .failure(.invalidURL)
        case .text:
            step = .failure(.invalidURL)
        }
    }

    func startPastedText() {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            step = .failure(.unsupportedSource)
            return
        }
        switch URLNormalizer.classify(text) {
        case .url(let url):
            urlText = text
            beginExtraction(url: url, fallbackText: nil, hint: nil)
        case .unsupportedURL:
            step = .failure(.unsupportedSource)
        case .empty:
            step = .failure(.unsupportedSource)
        case .text(let body):
            document = RecipeTextParser.document(from: body, origin: .imported)
            document.sourcePlatform = .unknown
            replacingSlug = nil
            armReview()
            step = .review
            Analytics.track(.importInputReceived, properties: ["method": "text"])
            Analytics.track(.importReviewOpened, properties: ["method": "text"])
        }
    }

    func beginShare(_ payload: SharedImportPayload) {
        _ = ShareHandoff.consume()
        Analytics.track(.importInputReceived, properties: ["method": "share"])
        if let raw = payload.urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            switch URLNormalizer.classify(raw) {
            case .url(let url):
                beginExtraction(url: url, fallbackText: payload.text, hint: payload.sourceHint)
                return
            case .unsupportedURL:
                step = .failure(.unsupportedSource)
                return
            case .empty, .text:
                break
            }
        }
        let text = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            step = .failure(.unsupportedSource)
            return
        }
        switch URLNormalizer.classify(text) {
        case .url(let url):
            beginExtraction(url: url, fallbackText: nil, hint: payload.sourceHint)
        case .text(let body):
            document = RecipeTextParser.document(from: body, origin: .imported)
            document.sourcePlatform = URLNormalizer.platform(sourceHint: payload.sourceHint, url: nil)
            armReview()
            step = .review
            Analytics.track(.importReviewOpened, properties: ["method": "share"])
        case .empty, .unsupportedURL:
            step = .failure(.unsupportedSource)
        }
    }

    func resume(_ draft: RecipeImportDraft) {
        guard let stored = RecipeImportService.document(from: draft) else {
            errorMessage = "Bu taslak açılamadı."
            return
        }
        document = stored
        draftID = draft.uuid
        replacingSlug = draft.linkedRecipeSlug.isEmpty ? nil : draft.linkedRecipeSlug
        armReview()
        step = .review
        Analytics.track(.importReviewOpened, properties: ["method": "draft"])
    }

    func cancelExtraction() {
        extractTask?.cancel()
        extractTask = nil
        step = .failure(.cancelled)
        Analytics.track(.importCancelled, properties: ["stage": "extract"])
    }

    func noteEdit() {
        guard editsArmed, let baseline else { return }
        if document != baseline, !document.isUserEdited {
            document.isUserEdited = true
            Analytics.track(.importReviewEdited)
        }
    }

    func requestSave(recipes: [Recipe]) {
        let decision = RecipeImportService.saveDecision(document)
        guard decision.canSave else {
            errorMessage = decision.blockers.first?.message
            return
        }
        if !skipDuplicateCheck {
            let matches = RecipeDuplicateService.matches(
                for: document,
                among: RecipeImportService.duplicateInputs(from: recipes),
                excludingSlug: replacingSlug
            )
            if let match = matches.first {
                duplicate = match
                step = .duplicate
                Analytics.track(.importDuplicateDetected, properties: ["strength": match.strength.rawValue])
                return
            }
        }
        confirmSave = true
    }

    func useExisting() {
        finishedSlug = duplicate?.slug
        Analytics.track(.importCancelled, properties: ["stage": "duplicate"])
    }

    func importAsSeparate() {
        skipDuplicateCheck = true
        replacingSlug = nil
        step = .review
        confirmSave = true
    }

    func reviewReimport(recipes: [Recipe]) {
        guard let duplicate, let recipe = recipes.first(where: { $0.slug == duplicate.slug }) else { return }
        let current = RecipeImportService.document(from: recipe)
        reimportChanges = RecipeDuplicateService.changes(from: current, to: document)
        selectedReimportFields = []
        replacingSlug = recipe.slug
        step = .reimport
    }

    func applySelectedReimport(recipes: [Recipe]) {
        guard let slug = replacingSlug, let recipe = recipes.first(where: { $0.slug == slug }) else { return }
        let current = RecipeImportService.document(from: recipe)
        document = current.applying(document, fields: selectedReimportFields)
        document.isUserEdited = true
        skipDuplicateCheck = true
        armReview()
        step = .review
        confirmSave = true
    }

    func keepCurrentRecipe() {
        finishedSlug = replacingSlug ?? duplicate?.slug
    }

    func commitSave(in context: ModelContext, drafts: [RecipeImportDraft]) {
        do {
            let result = try RecipeImportService.save(
                document,
                replacing: replacingSlug,
                recordEdit: document.isUserEdited && replacingSlug != nil,
                in: context
            )
            if let draftID, let draft = drafts.first(where: { $0.uuid == draftID }) {
                context.delete(draft)
                try context.save()
            }
            finishedSlug = result.slug
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDraft(in context: ModelContext, drafts: [RecipeImportDraft]) {
        let existing = draftID.flatMap { id in drafts.first { $0.uuid == id } }
        let state: RecipeDraftState = RecipeImportService.saveDecision(document).canSave ? .ready : .incomplete
        do {
            let draft = try RecipeImportService.saveDraft(
                document,
                state: state,
                existing: existing,
                linkedSlug: replacingSlug ?? "",
                in: context
            )
            draftID = draft.uuid
            errorMessage = nil
            step = .entry
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteDraft(_ draft: RecipeImportDraft, in context: ModelContext) {
        context.delete(draft)
        try? context.save()
    }

    func cancel() {
        extractTask?.cancel()
        Analytics.track(.importCancelled, properties: ["stage": "review"])
    }

    private func beginExtraction(url: URL, fallbackText: String?, hint: String?) {
        extractTask?.cancel()
        sharedFallbackText = fallbackText
        urlText = url.absoluteString
        step = .extracting
        Analytics.track(.importStarted, properties: ["method": "url"])
        Analytics.track(.importExtractionStarted, properties: [
            "platform": URLNormalizer.platform(for: url).rawValue,
        ])
        extractTask = Task { [url, hint] in
            let result = await RecipeExtractionService.load(url: url)
            guard !Task.isCancelled else {
                step = .failure(.cancelled)
                return
            }
            var next = result.document
            if let hint {
                let hostPlatform = URLNormalizer.platform(for: url)
                if hostPlatform == .website {
                    next.sourcePlatform = URLNormalizer.platform(sourceHint: hint, url: url)
                }
            }
            if let failure = result.failure {
                if let fallback = sharedFallbackText?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
                    var parsed = RecipeTextParser.document(from: fallback, origin: .imported)
                    parsed.sourceURL = next.sourceURL
                    parsed.sourcePlatform = next.sourcePlatform
                    parsed.sourceKey = next.sourceKey
                    document = parsed
                    armReview()
                    step = .review
                    Analytics.track(.importExtractionFailed, properties: ["reason": failure.token])
                    Analytics.track(.importManualFallbackUsed, properties: ["method": "share-text"])
                    return
                }
                document = next
                step = .failure(failure)
                Analytics.track(.importExtractionFailed, properties: ["reason": failure.token])
                return
            }
            document = next
            armReview()
            step = .review
            Analytics.track(.importExtractionCompleted, properties: [
                "platform": next.sourcePlatform.rawValue,
            ])
            Analytics.track(.importReviewOpened, properties: ["method": "url"])
        }
    }

    private func armReview() {
        baseline = document
        editsArmed = true
    }
}

private extension ImportFailure {
    var token: String {
        switch self {
        case .invalidURL: "invalid_url"
        case .unsupportedSource: "unsupported"
        case .missingRecipeData: "missing"
        case .network: "network"
        case .timeout: "timeout"
        case .parsing: "parsing"
        case .cancelled: "cancelled"
        }
    }
}

struct ImportFlowView: View {
    var launchPayload: SharedImportPayload?
    var editingSlug: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeImportDraft.updatedAt, order: .reverse) private var drafts: [RecipeImportDraft]
    @Query private var recipes: [Recipe]
    @State private var viewModel = ImportViewModel()
    @State private var didPrepare = false
    @State private var confirmManualReset = false

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            stepContent
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
                if viewModel.step == .review {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
                }
        }
        .task {
            guard !didPrepare else { return }
            didPrepare = true
            viewModel.prepare(editingSlug: editingSlug, recipes: recipes, payload: launchPayload)
        }
        .onChange(of: viewModel.document) { _, _ in
            viewModel.noteEdit()
        }
        .onChange(of: viewModel.finishedSlug) { _, slug in
            if slug != nil { dismiss() }
        }
        .alert("Kaydedilemedi", isPresented: errorIsPresented) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Elle girişe geçilsin mi?", isPresented: $confirmManualReset) {
            Button("Elle gir", role: .destructive) {
                viewModel.startManual(keepingSource: true)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Çıkarılan metin silinir. Kaynak adresi durur.")
        }
        .alert("Tarif kaydedilsin mi?", isPresented: $viewModel.confirmSave) {
            Button("Kaydet") {
                viewModel.commitSave(in: modelContext, drafts: drafts)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kaydettikten sonra bu tarif plan, market listesi ve yemek hafızasında kullanılır. İçe aktarmak favori yapmak değildir.")
        }
    }

    private var title: String {
        switch viewModel.step {
        case .entry: "Tarif ekle"
        case .extracting: "Tarif aranıyor"
        case .review: "Tarifi incele"
        case .failure: "Tarif alınamadı"
        case .duplicate: "Benzer tarif"
        case .reimport: "Değişiklikler"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .entry:
            entry
        case .extracting:
            extracting
        case .review:
            review
        case .failure(let failure):
            failureView(failure)
        case .duplicate:
            duplicateView
        case .reimport:
            reimportView
        }
    }

    @ViewBuilder
    private var entry: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Bağlantı") {
                TextField("Tarif linki", text: $viewModel.urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button("Linkten çıkar") { viewModel.startURL() }
            }
            Section("Metin") {
                TextField("Tarif metnini yapıştır", text: $viewModel.pastedText, axis: .vertical)
                    .lineLimit(4...8)
                Button("Metni ayır") { viewModel.startPastedText() }
            }
            Section {
                Button("Elle gir") { viewModel.startManual() }
            } footer: {
                Text("Otomatik çıkarma başarısız olursa tarif burada elle yazılır. Eksik miktar uydurulmaz.")
            }
            if !drafts.isEmpty {
                Section("Taslaklar") {
                    ForEach(drafts, id: \.uuid) { draft in
                        Button {
                            viewModel.resume(draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title.isEmpty ? "Adsız taslak" : draft.title)
                                    .font(.body.weight(.semibold))
                                Text(draftStateTitle(draft.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteDraft(drafts[index], in: modelContext)
                        }
                    }
                }
            }
        }
    }

    private var extracting: some View {
        VStack(spacing: 16) {
            ProgressView("Tarif sayfası okunuyor…")
            Button("İptal et", role: .cancel) { viewModel.cancelExtraction() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private func failureView(_ failure: ImportFailure) -> some View {
        ContentUnavailableView {
            Label("Tarif alınamadı", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            Button("Yeniden dene") { viewModel.startURL() }
                .buttonStyle(.borderedProminent)
            Button("Metni yapıştır") { viewModel.step = .entry }
            Button("Elle gir") { viewModel.startManual(keepingSource: true) }
        }
    }

    private var duplicateView: some View {
        Form {
            if let duplicate = viewModel.duplicate {
                Section("Koleksiyonda") {
                    Text(duplicate.title)
                        .font(.headline)
                    Text(duplicate.reason)
                        .foregroundStyle(.secondary)
                }
                Section("Yeni tarif") {
                    Text(viewModel.document.title)
                }
            }
            Section {
                Button("Mevcut tarifi kullan") { viewModel.useExisting() }
                Button("Ayrı tarif olarak kaydet") { viewModel.importAsSeparate() }
                Button("Değişiklikleri incele") { viewModel.reviewReimport(recipes: recipes) }
                Button("Vazgeç", role: .cancel) { viewModel.step = .review }
            } footer: {
                Text("Mevcut tarifin üzerine sessizce yazılmaz. Düzenlediğin alanlar ancak sen seçersen değişir.")
            }
        }
    }

    private var reimportView: some View {
        Form {
            if viewModel.reimportChanges.isEmpty {
                Section {
                    Text("Çıkarılan metin mevcut tarifle aynı.")
                }
                Button("Mevcut hâli koru") { viewModel.keepCurrentRecipe() }
            } else {
                Section("Değişen alanlar") {
                    ForEach(viewModel.reimportChanges) { change in
                        Toggle(isOn: reimportBinding(change.field)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.field.titleText)
                                    .font(.subheadline.weight(.semibold))
                                Text("Şimdi: \(change.currentText.isEmpty ? "—" : change.currentText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Text("Yeni: \(change.incomingText.isEmpty ? "—" : change.incomingText)")
                                    .font(.caption)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
                Section {
                    Button("Seçilenleri değiştir") { viewModel.applySelectedReimport(recipes: recipes) }
                        .disabled(viewModel.selectedReimportFields.isEmpty)
                    Button("Mevcut hâli koru") { viewModel.keepCurrentRecipe() }
                }
            }
        }
    }

    @ViewBuilder
    private var review: some View {
        @Bindable var viewModel = viewModel
        Form {
            sourceSection
            basicSection
            ingredientSection
            instructionSection
            if !viewModel.document.warnings.isEmpty {
                Section("Uyarılar") {
                    ForEach(viewModel.document.warnings, id: \.rawValue) { warning in
                        Text(warning.message)
                    }
                }
            }
            if viewModel.document.warnings.contains(.missingIngredients) {
                Toggle("Malzemesiz kaydetmeyi onaylıyorum", isOn: $viewModel.document.confirmedMissingIngredients)
            }
            if viewModel.document.warnings.contains(.missingInstructions) {
                Toggle("Yapılışsız kaydetmeyi onaylıyorum", isOn: $viewModel.document.confirmedMissingInstructions)
            }
            Section {
                Button("Tarifi kaydet") { viewModel.requestSave(recipes: recipes) }
                    .font(.body.weight(.semibold))
                Button("Taslak olarak sakla") {
                    viewModel.saveDraft(in: modelContext, drafts: drafts)
                }
                Button("Elle gir") { beginManualEntry() }
                if !viewModel.document.sourceURL.isEmpty {
                    Button("Yeniden dene") {
                        viewModel.urlText = viewModel.document.sourceURL
                        viewModel.startURL()
                    }
                }
            } footer: {
                Text("Kaydetmeden önce kontrol et. MealRoutine bu metni kendi tarifi gibi göstermez.")
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        @Bindable var viewModel = viewModel
        Section("Kaynak") {
            if viewModel.document.sourceURL.isEmpty {
                Text("Kaynak adresi yok")
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.document.sourceURL)
                    .font(.footnote)
                    .textSelection(.enabled)
                if let url = URL(string: viewModel.document.sourceURL) {
                    Link("Kaynağı aç", destination: url)
                        .simultaneousGesture(TapGesture().onEnded {
                            Analytics.track(.importSourceOpened, properties: [
                                "platform": viewModel.document.sourcePlatform.rawValue,
                            ])
                        })
                }
            }
            LabeledContent("Platform", value: viewModel.document.sourcePlatform.title)
            TextField("Kaynak başlığı", text: $viewModel.document.sourceTitle)
            if let imported = drafts.first(where: { $0.uuid == viewModel.draftID }) {
                LabeledContent("İçe aktarma", value: imported.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private var basicSection: some View {
        @Bindable var viewModel = viewModel
        Section("Temel bilgiler") {
            TextField("Ad", text: $viewModel.document.title)
            TextField("Açıklama", text: $viewModel.document.summary, axis: .vertical)
                .lineLimit(2...5)
            TextField("Kategori", text: $viewModel.document.category)
            TextField("Mutfak", text: $viewModel.document.cuisine)
            minuteField("Hazırlık (dk)", value: $viewModel.document.prepMinutes)
            minuteField("Pişirme (dk)", value: $viewModel.document.cookMinutes)
            minuteField("Toplam (dk)", value: $viewModel.document.totalMinutes)
            servingsField
            Picker("Zorluk", selection: $viewModel.document.difficulty) {
                Text("Bilinmiyor").tag("unknown")
                Text("Kolay").tag("easy")
                Text("Orta").tag("medium")
                Text("Zor").tag("hard")
            }
            TextField("Notların", text: $viewModel.document.notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var ingredientSection: some View {
        @Bindable var viewModel = viewModel
        Section("Malzemeler") {
            ForEach($viewModel.document.ingredients) { $ingredient in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Malzeme", text: $ingredient.name)
                    HStack {
                        TextField("Miktar", text: quantityBinding($ingredient))
                            .keyboardType(.decimalPad)
                        TextField("Birim", text: unitBinding($ingredient))
                    }
                    TextField("Hazırlık notu", text: noteBinding($ingredient))
                    if !ingredient.originalText.isEmpty {
                        Text(ingredient.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if ingredient.isUncertain {
                        Text("Miktar belirsiz")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Toggle("İsteğe bağlı", isOn: $ingredient.isOptional)
                    Toggle("Markete ekle", isOn: $ingredient.includeInGrocery)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                viewModel.document.ingredients.remove(atOffsets: offsets)
                reindexIngredients()
            }
            .onMove { source, destination in
                viewModel.document.ingredients.move(fromOffsets: source, toOffset: destination)
                reindexIngredients()
            }
            Button("Malzeme ekle") {
                viewModel.document.ingredients.append(
                    ImportedIngredient(
                        name: "",
                        isUncertain: true,
                        sortOrder: viewModel.document.ingredients.count,
                        includeInGrocery: false
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var instructionSection: some View {
        @Bindable var viewModel = viewModel
        Section("Yapılış") {
            ForEach($viewModel.document.instructions) { $step in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Adım", text: $step.text, axis: .vertical)
                        .lineLimit(2...6)
                    if step.isUncertain {
                        Text("Bu adım metinden tahmin edildi")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .onDelete { offsets in
                viewModel.document.instructions.remove(atOffsets: offsets)
                reindexSteps()
            }
            .onMove { source, destination in
                viewModel.document.instructions.move(fromOffsets: source, toOffset: destination)
                reindexSteps()
            }
            Button("Adım ekle") {
                viewModel.document.instructions.append(
                    ImportedInstruction(text: "", sortOrder: viewModel.document.instructions.count)
                )
            }
        }
    }

    private var servingsField: some View {
        TextField("Porsiyon", text: servingsBinding)
            .keyboardType(.numberPad)
    }

    private var servingsBinding: Binding<String> {
        Binding(
            get: { viewModel.document.servings.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                viewModel.document.servings = Int(digits)
            }
        )
    }

    private func minuteField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                value.wrappedValue = Int(digits)
            }
        ))
        .keyboardType(.numberPad)
    }

    private func quantityBinding(_ ingredient: Binding<ImportedIngredient>) -> Binding<String> {
        Binding(
            get: {
                guard let quantity = ingredient.wrappedValue.quantity else { return "" }
                return quantity.formatted(.number.precision(.fractionLength(0...2)))
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    ingredient.wrappedValue.quantity = nil
                    ingredient.wrappedValue.isUncertain = true
                    return
                }
                let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
                ingredient.wrappedValue.quantity = Double(normalized)
                ingredient.wrappedValue.isUncertain = ingredient.wrappedValue.quantity == nil
            }
        )
    }

    private func unitBinding(_ ingredient: Binding<ImportedIngredient>) -> Binding<String> {
        Binding(
            get: { ingredient.wrappedValue.unit ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                ingredient.wrappedValue.unit = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func noteBinding(_ ingredient: Binding<ImportedIngredient>) -> Binding<String> {
        Binding(
            get: { ingredient.wrappedValue.preparationNote ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                ingredient.wrappedValue.preparationNote = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func reimportBinding(_ field: ReimportField) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedReimportFields.contains(field) },
            set: { isOn in
                if isOn {
                    viewModel.selectedReimportFields.insert(field)
                } else {
                    viewModel.selectedReimportFields.remove(field)
                }
            }
        )
    }

    private func reindexIngredients() {
        for index in viewModel.document.ingredients.indices {
            viewModel.document.ingredients[index].sortOrder = index
        }
    }

    private func reindexSteps() {
        for index in viewModel.document.instructions.indices {
            viewModel.document.instructions[index].sortOrder = index
        }
    }

    private func beginManualEntry() {
        let title = viewModel.document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasIngredient = viewModel.document.ingredients.contains {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasStep = viewModel.document.instructions.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if title.isEmpty && !hasIngredient && !hasStep {
            viewModel.startManual(keepingSource: true)
        } else {
            confirmManualReset = true
        }
    }

    private func draftStateTitle(_ state: RecipeDraftState) -> String {
        switch state {
        case .started: "Başladı"
        case .extracting: "Çıkarılıyor"
        case .needsReview: "İnceleme bekliyor"
        case .incomplete: "Eksik"
        case .ready: "Kayda hazır"
        case .cancelled: "İptal"
        case .failed: "Başarısız"
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }
}
