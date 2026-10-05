import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One editor for Yeni tarif, Tarifi tamamla, and Düzenle. The cook types the recipe.
struct RecipeEditorView: View {
    var launch: RecipeEditorLaunch
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @State private var form = RecipeForm.emptyManual()
    @State private var baseline = RecipeForm.emptyManual()
    @State private var issues: [RecipeValidationIssue] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showsDiscard = false
    @State private var duplicateSlug: String?
    @State private var allowDuplicate = false
    @State private var didSave = false
    @State private var startedCompletion = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var focusToken = 0
    @FocusState private var focusedField: RecipeEditorField?

    private var existing: Recipe? {
        guard let slug = launch.slug else { return nil }
        return recipes.first { $0.slug == slug && !$0.isBundledCatalog }
    }

    private var title: String {
        guard let existing else { return "Yeni tarif" }
        return existing.collectionState == .savedToTry ? "Tarifi tamamla" : "Tarifi düzenle"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if !issues.isEmpty {
                        Section("Kaydetmeden önce") {
                            ForEach(issues) { issue in
                                Text(issue.message)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    identitySection
                    ingredientSection
                    stepSection
                    timeSection
                    detailSection
                    sourceSection
                }
                .onChange(of: focusToken) { _, _ in
                    guard let field = RecipeValidationService.invalidFields(in: form).first else { return }
                    focusedField = field
                    withAnimation {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { requestDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .alert("Değişiklikler kaybolsun mu?", isPresented: $showsDiscard) {
                Button("Düzenlemeye devam", role: .cancel) {}
                Button("Vazgeç", role: .destructive) { closeWithoutSaving() }
            } message: {
                Text("Yazdıkların silinir.")
            }
            .alert("Bu kaynak zaten kayıtlı", isPresented: duplicateIsPresented) {
                Button("Tarifi aç") { openDuplicate() }
                Button("Yine de kaydet") {
                    allowDuplicate = true
                    save()
                }
                Button("Düzenlemeye devam", role: .cancel) {}
            } message: {
                Text("Aynı adres sessizce üzerine yazılmaz.")
            }
            .alert("Kaydedilemedi", isPresented: errorIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var identitySection: some View {
        Section("Tarif") {
            validatedField(.name) {
                TextField("Ad", text: limitedText(\.name, maxCharacters: RecipeFieldLimits.name))
            }
            validatedField(.servings) {
                TextField("Porsiyon", text: servingsText)
                    .keyboardType(.numberPad)
            }
            if let image = localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
                    .clipped()
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(form.sourceImagePath.isEmpty ? "Fotoğraf ekle" : "Fotoğrafı değiştir", systemImage: "photo")
            }
        }
    }

    private var ingredientSection: some View {
        Section("Malzemeler") {
            ForEach(Array(form.ingredients.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    validatedField(.ingredientName(index)) {
                        TextField("Malzeme", text: ingredientName(index))
                    }
                    HStack(alignment: .top) {
                        validatedField(.ingredientQuantity(index)) {
                            TextField("Miktar", text: quantityText(index))
                                .keyboardType(.decimalPad)
                        }
                        validatedField(.ingredientUnit(index)) {
                            unitPicker(index)
                        }
                    }
                    validatedField(.ingredientNote(index)) {
                        TextField("Hazırlık notu", text: preparationNote(index))
                    }
                    Toggle("İsteğe bağlı", isOn: $form.ingredients[index].isOptional)
                    HStack {
                        Button("Yukarı") { moveIngredient(index, by: -1) }
                        Button("Aşağı") { moveIngredient(index, by: 1) }
                        Spacer()
                        Button("Sil", role: .destructive) {
                            form.ingredients.remove(at: index)
                            if form.ingredients.isEmpty { form.ingredients = [RecipeFormIngredient()] }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Malzeme ekle") {
                form.ingredients.append(RecipeFormIngredient())
            }
        }
    }

    private var stepSection: some View {
        Section("Yapılış") {
            ForEach(Array(form.steps.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    validatedField(.step(index)) {
                        TextField("Adım", text: stepText(index), axis: .vertical)
                    }
                    HStack {
                        Button("Yukarı") { moveStep(index, by: -1) }
                        Button("Aşağı") { moveStep(index, by: 1) }
                        Spacer()
                        Button("Sil", role: .destructive) {
                            form.steps.remove(at: index)
                            if form.steps.isEmpty { form.steps = [""] }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Adım ekle") { form.steps.append("") }
        }
    }

    private var timeSection: some View {
        Section("Süre") {
            validatedField(.prepMinutes) {
                TextField("Hazırlık (dk)", text: minutesText(\.prepMinutesText, \.prepMinutes))
                    .keyboardType(.numberPad)
            }
            validatedField(.cookMinutes) {
                TextField("Pişirme (dk)", text: minutesText(\.cookMinutesText, \.cookMinutes))
                    .keyboardType(.numberPad)
            }
            validatedField(.totalMinutes) {
                TextField("Toplam (dk)", text: minutesText(\.totalMinutesText, \.totalMinutes))
                    .keyboardType(.numberPad)
            }
            Text("Boş süre uydurulmaz. Bilinmeyen süre planda sayı olarak görünmez.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailSection: some View {
        Section("Ayrıntı") {
            validatedField(.category) {
                TextField("Kategori", text: limitedText(\.category, maxCharacters: RecipeFieldLimits.category))
            }
            validatedField(.cuisine) {
                TextField("Mutfak", text: limitedText(\.cuisine, maxCharacters: RecipeFieldLimits.cuisine))
            }
            Picker("Zorluk", selection: $form.difficulty) {
                Text("Seçilmedi").tag("")
                Text("Kolay").tag("easy")
                Text("Orta").tag("medium")
                Text("Zor").tag("hard")
            }
            validatedField(.notes) {
                TextField("Not", text: limitedText(\.notes, maxCharacters: RecipeFieldLimits.notes), axis: .vertical)
            }
        }
    }

    private var sourceSection: some View {
        Section("Kaynak") {
            Text(form.sourcePlatform.title)
                .foregroundStyle(.secondary)
            validatedField(.sourceURL) {
                TextField("Kaynak adresi", text: limitedText(\.sourceURL, maxCharacters: RecipeFieldLimits.sourceURL))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            validatedField(.sourceTitle) {
                TextField("Kaynak başlığı", text: limitedText(\.sourceTitle, maxCharacters: RecipeFieldLimits.sourceTitle))
            }
            if let url = RecipeSourceService.publicURL(form.sourceURL) {
                Link("Orijinali aç", destination: url)
            }
        }
    }

    private var localImage: UIImage? {
        guard let url = RecipeCaptureStore.resolve(form.sourceImagePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func limitedText(
        _ keyPath: WritableKeyPath<RecipeForm, String>,
        maxCharacters: Int
    ) -> Binding<String> {
        Binding(
            get: { form[keyPath: keyPath] },
            set: { form[keyPath: keyPath] = RecipeTextLimit.clamp($0, maxCharacters: maxCharacters) }
        )
    }

    private func ingredientName(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.ingredients.indices.contains(index) else { return "" }
                return form.ingredients[index].name
            },
            set: { text in
                guard form.ingredients.indices.contains(index) else { return }
                form.ingredients[index].name = RecipeTextLimit.clamp(text, maxCharacters: RecipeFieldLimits.ingredientName)
            }
        )
    }

    private func preparationNote(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.ingredients.indices.contains(index) else { return "" }
                return form.ingredients[index].preparationNote
            },
            set: { text in
                guard form.ingredients.indices.contains(index) else { return }
                form.ingredients[index].preparationNote = RecipeTextLimit.clamp(
                    text,
                    maxCharacters: RecipeFieldLimits.preparationNote
                )
            }
        )
    }

    private func stepText(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.steps.indices.contains(index) else { return "" }
                return form.steps[index]
            },
            set: { text in
                guard form.steps.indices.contains(index) else { return }
                form.steps[index] = RecipeTextLimit.clamp(text, maxCharacters: RecipeFieldLimits.step)
            }
        )
    }

    private var servingsText: Binding<String> {
        Binding(
            get: {
                if !form.servingsText.isEmpty { return form.servingsText }
                return form.servings.map(String.init) ?? ""
            },
            set: { raw in
                let clamped = RecipeTextLimit.clamp(raw, maxCharacters: RecipeFieldLimits.servingsDigits)
                form.servingsText = clamped
                switch RecipeNumericInput.whole(clamped, maxDigits: RecipeFieldLimits.servingsDigits) {
                case .value(let number):
                    form.servings = number
                case .empty:
                    form.servings = nil
                case .notANumber, .tooManyDigits:
                    form.servings = nil
                }
            }
        )
    }

    private func quantityText(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.ingredients.indices.contains(index) else { return "" }
                let line = form.ingredients[index]
                if !line.quantityText.isEmpty { return line.quantityText }
                return line.quantity.map(Self.quantityDisplay) ?? ""
            },
            set: { text in
                guard form.ingredients.indices.contains(index) else { return }
                let clamped = RecipeTextLimit.clamp(text, maxCharacters: RecipeFieldLimits.quantityCharacters)
                form.ingredients[index].quantityText = clamped
                switch RecipeNumericInput.decimal(clamped) {
                case .value(let number):
                    form.ingredients[index].quantity = number
                case .empty:
                    form.ingredients[index].quantity = nil
                case .notANumber, .tooLong:
                    form.ingredients[index].quantity = nil
                }
            }
        )
    }

    private func minutesText(
        _ textKey: WritableKeyPath<RecipeForm, String>,
        _ valueKey: WritableKeyPath<RecipeForm, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                let typed = form[keyPath: textKey]
                if !typed.isEmpty { return typed }
                return form[keyPath: valueKey].map(String.init) ?? ""
            },
            set: { raw in
                let clamped = RecipeTextLimit.clamp(raw, maxCharacters: RecipeFieldLimits.minutesDigits)
                form[keyPath: textKey] = clamped
                switch RecipeNumericInput.whole(clamped, maxDigits: RecipeFieldLimits.minutesDigits) {
                case .value(let number) where number > 0:
                    form[keyPath: valueKey] = number
                case .empty:
                    form[keyPath: valueKey] = nil
                case .value, .notANumber, .tooManyDigits:
                    form[keyPath: valueKey] = nil
                }
            }
        )
    }

    /// Plain digits and a dot, so a loaded quantity round-trips without locale grouping.
    private static func quantityDisplay(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value, abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        let rounded = (value * 100).rounded() / 100
        return String(rounded)
    }

    private func moveIngredient(_ index: Int, by offset: Int) {
        let next = index + offset
        guard form.ingredients.indices.contains(index), form.ingredients.indices.contains(next) else { return }
        form.ingredients.swapAt(index, next)
    }

    private func moveStep(_ index: Int, by offset: Int) {
        let next = index + offset
        guard form.steps.indices.contains(next) else { return }
        form.steps.swapAt(index, next)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            form = RecipeCollectionService.form(from: existing)
            canonicalizeUnits()
            if existing.collectionState == .savedToTry && !startedCompletion {
                startedCompletion = true
                Analytics.track(.recipeCompletionStarted, properties: [
                    "origin": existing.origin.rawValue,
                    "platform": existing.sourcePlatform?.rawValue ?? "unknown",
                    "state": existing.collectionState.rawValue,
                ])
            }
        } else {
            form = RecipeForm.emptyManual()
            canonicalizeUnits()
        }
        syncNumericDrafts()
        baseline = form
    }

    /// Copies stored numbers into the text drafts so Kaydet reads the same value the field shows.
    private func syncNumericDrafts() {
        if form.servingsText.isEmpty, let servings = form.servings, servings > 0 {
            form.servingsText = String(servings)
        }
        if form.prepMinutesText.isEmpty, let minutes = form.prepMinutes, minutes > 0 {
            form.prepMinutesText = String(minutes)
        }
        if form.cookMinutesText.isEmpty, let minutes = form.cookMinutes, minutes > 0 {
            form.cookMinutesText = String(minutes)
        }
        if form.totalMinutesText.isEmpty, let minutes = form.totalMinutes, minutes > 0 {
            form.totalMinutesText = String(minutes)
        }
        for index in form.ingredients.indices {
            guard form.ingredients[index].quantityText.isEmpty,
                  let quantity = form.ingredients[index].quantity,
                  quantity > 0 else { continue }
            form.ingredients[index].quantityText = Self.quantityDisplay(quantity)
        }
    }

    private func requestDismiss() {
        if form != baseline {
            showsDiscard = true
        } else {
            closeWithoutSaving()
        }
    }

    private func closeWithoutSaving() {
        if startedCompletion && !didSave, let existing {
            Analytics.track(.recipeCompletionAbandoned, properties: [
                "origin": existing.origin.rawValue,
                "platform": existing.sourcePlatform?.rawValue ?? "unknown",
                "state": existing.collectionState.rawValue,
            ])
        }
        dismiss()
    }

    private func save() {
        canonicalizeUnits()
        let result = RecipeValidationService.validate(form)
        issues = result.issues
        guard result == .valid else {
            focusToken += 1
            return
        }
        do {
            _ = try RecipeCollectionService.save(
                form,
                slug: existing?.slug,
                allowDuplicate: allowDuplicate,
                in: modelContext
            )
            didSave = true
            dismiss()
        } catch RecipeCollectionError.duplicateSource(let slug) {
            duplicateSlug = slug
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDuplicate() {
        if let duplicateSlug {
            CollectionRouter.shared.openSlug = duplicateSlug
        }
        didSave = true
        dismiss()
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let payload = try? await item.loadTransferable(type: EditorImageFile.self),
              let image = UIImage(data: payload.data),
              let jpeg = image.jpegData(compressionQuality: 0.85),
              let path = try? RecipeCaptureStore.saveImage(jpeg, id: UUID()) else { return }
        form.sourceImagePath = path
    }

    private var duplicateIsPresented: Binding<Bool> {
        Binding(
            get: { duplicateSlug != nil },
            set: { if !$0 { duplicateSlug = nil } }
        )
    }

    private var showsFieldErrors: Bool {
        !issues.isEmpty
    }

    private func canonicalizeUnits() {
        for index in form.ingredients.indices {
            form.ingredients[index].unit = RecipeUnitChoices.canonical(form.ingredients[index].unit)
        }
    }

    private func unitSelection(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.ingredients.indices.contains(index) else { return "" }
                return RecipeUnitChoices.canonical(form.ingredients[index].unit)
            },
            set: { newValue in
                guard form.ingredients.indices.contains(index) else { return }
                form.ingredients[index].unit = newValue
            }
        )
    }

    private func unitOptions(_ index: Int) -> [String] {
        let current = form.ingredients.indices.contains(index)
            ? RecipeUnitChoices.canonical(form.ingredients[index].unit)
            : ""
        if current.isEmpty || RecipeUnitChoices.codes.contains(current) {
            return RecipeUnitChoices.codes
        }
        return RecipeUnitChoices.codes + [current]
    }

    private func unitPicker(_ index: Int) -> some View {
        Picker("Birim", selection: unitSelection(index)) {
            Text("Birim yok").tag("")
            ForEach(unitOptions(index), id: \.self) { code in
                Text(UnitLabels.turkish(code)).tag(code)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Birim")
    }

    @ViewBuilder
    private func validatedField<Content: View>(
        _ field: RecipeEditorField,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let invalid = showsFieldErrors && RecipeValidationService.invalidFields(in: form).contains(field)
        VStack(alignment: .leading, spacing: 4) {
            content()
                .focused($focusedField, equals: field)
            if invalid {
                Text(RecipeValidationService.message(for: field, in: form))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .id(field)
        .padding(invalid ? 6 : 0)
        .background(invalid ? Color.red.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(invalid ? Color.red : Color.clear, lineWidth: 1)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

/// Photo library bytes. The editor stores a local JPEG and does not keep a remote image URL.
private struct EditorImageFile: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            EditorImageFile(data: data)
        }
    }
}
