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
            Form {
                identitySection
                ingredientSection
                stepSection
                timeSection
                detailSection
                sourceSection
                if !issues.isEmpty {
                    Section("Kaydetmeden önce") {
                        ForEach(issues) { issue in
                            Text(issue.message)
                        }
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
            TextField("Ad", text: $form.name)
            TextField("Porsiyon", text: servingsText)
                .keyboardType(.numberPad)
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
                    TextField("Malzeme", text: $form.ingredients[index].name)
                    HStack {
                        TextField("Miktar", text: quantityText(index))
                            .keyboardType(.decimalPad)
                        TextField("Birim", text: $form.ingredients[index].unit)
                    }
                    TextField("Hazırlık notu", text: $form.ingredients[index].preparationNote)
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
                    TextField("Adım", text: $form.steps[index], axis: .vertical)
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
            TextField("Hazırlık (dk)", text: minutesText(\.prepMinutes))
                .keyboardType(.numberPad)
            TextField("Pişirme (dk)", text: minutesText(\.cookMinutes))
                .keyboardType(.numberPad)
            TextField("Toplam (dk)", text: minutesText(\.totalMinutes))
                .keyboardType(.numberPad)
            Text("Boş süre uydurulmaz. Bilinmeyen süre planda sayı olarak görünmez.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailSection: some View {
        Section("Ayrıntı") {
            TextField("Kategori", text: $form.category)
            TextField("Mutfak", text: $form.cuisine)
            Picker("Zorluk", selection: $form.difficulty) {
                Text("Seçilmedi").tag("")
                Text("Kolay").tag("easy")
                Text("Orta").tag("medium")
                Text("Zor").tag("hard")
            }
            TextField("Not", text: $form.notes, axis: .vertical)
        }
    }

    private var sourceSection: some View {
        Section("Kaynak") {
            Text(form.sourcePlatform.title)
                .foregroundStyle(.secondary)
            TextField("Kaynak adresi", text: $form.sourceURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            TextField("Kaynak başlığı", text: $form.sourceTitle)
            if let url = RecipeSourceService.publicURL(form.sourceURL) {
                Link("Orijinali aç", destination: url)
            }
        }
    }

    private var localImage: UIImage? {
        guard let url = RecipeCaptureStore.resolve(form.sourceImagePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var servingsText: Binding<String> {
        Binding(
            get: { form.servings.map(String.init) ?? "" },
            set: { form.servings = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private func quantityText(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard form.ingredients.indices.contains(index),
                      let quantity = form.ingredients[index].quantity else { return "" }
                return quantity.formatted(.number.precision(.fractionLength(0...2)))
            },
            set: { text in
                guard form.ingredients.indices.contains(index) else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                if trimmed.isEmpty {
                    form.ingredients[index].quantity = nil
                } else {
                    form.ingredients[index].quantity = Double(trimmed)
                }
            }
        )
    }

    private func minutesText(_ keyPath: WritableKeyPath<RecipeForm, Int?>) -> Binding<String> {
        Binding(
            get: { form[keyPath: keyPath].map(String.init) ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                form[keyPath: keyPath] = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
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
        }
        baseline = form
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
        let result = RecipeValidationService.validate(form)
        issues = result.issues
        guard result == .valid else { return }
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
