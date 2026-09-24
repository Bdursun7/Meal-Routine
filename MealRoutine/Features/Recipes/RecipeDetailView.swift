import SwiftData
import SwiftUI

/// Who the portion stepper on recipe detail writes to.
private struct PortionContext: Equatable {
    var contextID: String
    var persisted: Int
    var mealUUID: UUID?
}

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @Query private var prefs: [UserPrefs]
    @Query private var plannedMeals: [PlannedMeal]

    let route: RecipeRoute
    @State private var viewModel = RecipeDetailViewModel()
    /// Unsaved stepper value. Nil follows the stored count for this context.
    @State private var portionDraft: Int?
    @State private var portionDraftContext: String?
    /// Last count this screen successfully wrote, so a later household save can replace it.
    @State private var lastWrittenServings: Int?
    @State private var lastWrittenContext: String?
    @State private var isHeroPhotoShown = false
    /// Cook-along checks. Local to this screen; they are not saved.
    @State private var checkedIngredientKeys: Set<String> = []

    private var recipe: Recipe? {
        recipes.first { $0.slug == route.slug }
    }

    private var currentRating: MealRating? {
        guard let recipe else { return nil }
        return FeedbackIndex.latestRatings(in: feedback)[recipe.slug]
    }

    var body: some View {
        Group {
            if let recipe {
                content(recipe)
            } else {
                ContentUnavailableView(
                    "Tarif bulunamadı",
                    systemImage: "questionmark.circle",
                    description: Text(route.slug)
                )
            }
        }
        .navigationTitle(recipe?.displayName ?? "Tarif")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: viewModel.savedNotice == nil ? 0 : 12) {
            Group {
                if let notice = viewModel.savedNotice {
                    SavedRatingToast(notice: notice, onDismiss: viewModel.dismissSavedNotice)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.savedNotice?.id)
        }
        .overlay {
            Group {
                if viewModel.isShowingRatingPrompt {
                    CookRatingPrompt(
                        currentRating: currentRating,
                        onSelect: { rating in
                            viewModel.saveRating(rating: rating, slug: route.slug, in: modelContext)
                        },
                        onCancel: viewModel.cancelRating
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isShowingRatingPrompt)
            .allowsHitTesting(viewModel.isShowingRatingPrompt)
        }
        .sensoryFeedback(.success, trigger: viewModel.savedNotice?.id) { _, newValue in
            newValue != nil
        }
        .onChange(of: viewModel.savedNotice?.id) { _, newID in
            guard newID != nil, let notice = viewModel.savedNotice else { return }
            AccessibilityNotification.Announcement(notice.message).post()
        }
        .task(id: viewModel.savedNotice?.id) {
            guard viewModel.savedNotice != nil else { return }
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            viewModel.dismissSavedNotice()
        }
        .onAppear {
            Analytics.track(.recipeOpened)
        }
        .alert(
            "Kaydedilemedi",
            isPresented: alertIsPresented
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Kaydedildi", isPresented: portionStatusIsPresented) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.portionStatusMessage ?? "")
        }
        .onChange(of: portionContext) { _, newContext in
            let draftMatchesWrite = portionDraft == lastWrittenServings || portionDraft == newContext.persisted
            guard portionDraftContext == newContext.contextID,
                  lastWrittenContext == newContext.contextID,
                  draftMatchesWrite
            else { return }
            portionDraft = nil
            portionDraftContext = nil
        }
    }

    private var householdSize: Int {
        let stored = prefs.min { $0.createdAt < $1.createdAt }?.householdSize ?? 2
        return HouseholdSizeLimits.clamped(stored)
    }

    private var portionContext: PortionContext {
        if let mealUUID = route.plannedMealUUID,
           let meal = plannedMeals.first(where: { $0.uuid == mealUUID }) {
            return PortionContext(
                contextID: mealUUID.uuidString,
                persisted: ActiveServings.resolve(
                    mealServings: meal.servings,
                    householdSize: householdSize
                ),
                mealUUID: mealUUID
            )
        }
        return PortionContext(
            contextID: "household",
            persisted: householdSize,
            mealUUID: nil
        )
    }

    /// Servings the ingredient list is showing. The stepper can move this before save.
    private var activeServings: Int {
        if portionDraftContext == portionContext.contextID, let portionDraft {
            return portionDraft
        }
        return portionContext.persisted
    }

    private var servingsBinding: Binding<Int> {
        Binding(
            get: { activeServings },
            set: { newValue in
                portionDraftContext = portionContext.contextID
                portionDraft = HouseholdSizeLimits.clamped(newValue)
            }
        )
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }

    private var portionStatusIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.portionStatusMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.portionStatusMessage = nil }
            }
        )
    }

    @ViewBuilder
    private func content(_ recipe: Recipe) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.displayName)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(recipe.totalMinutes) dk · \(activeServings) kişilik")
                        .foregroundStyle(.secondary)
                    Text("\(DifficultyLabel.turkish(recipe.difficulty)) · \(CategoryLabel.turkish(recipe.unitoolsCategory)) · \(RegionLabel.turkish(recipe.country))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    RecipePhotoView(
                        urlString: recipe.photoURL,
                        author: recipe.photoAuthor,
                        license: recipe.photoLicense,
                        layout: .hero,
                        isPhotoShown: $isHeroPhotoShown
                    )
                }
                .padding(.vertical, 4)
                if let currentRating {
                    currentRatingRow(currentRating)
                }
                favoriteButton(isLoved: currentRating == .loved)
            }

            if !recipe.displaySummary.isEmpty {
                Section("Özet") {
                    Text(recipe.displaySummary)
                }
            }

            if !recipe.diets.isEmpty {
                Section("Beslenme") {
                    Text(recipe.diets.map(DietLabel.turkish).joined(separator: " · "))
                }
            }

            Section {
                Stepper(value: servingsBinding, in: HouseholdSizeLimits.range) {
                    Text(portionContext.mealUUID == nil
                         ? "Ev halkı: \(activeServings) kişi"
                         : "Bu akşam: \(activeServings) kişi")
                }
                .accessibilityLabel("Porsiyon \(activeServings) kişi")
                Text(portionFootnote(baseServings: recipe.baseServings))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Porsiyonu kaydet") {
                    let saved = activeServings
                    let contextID = portionContext.contextID
                    viewModel.savePortions(
                        servings: saved,
                        mealUUID: portionContext.mealUUID,
                        in: modelContext
                    )
                    if viewModel.errorMessage == nil {
                        lastWrittenContext = contextID
                        lastWrittenServings = saved
                        portionDraftContext = contextID
                        portionDraft = saved
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHint(portionContext.mealUUID == nil
                    ? "Ev halkını kaydeder, bu haftanın akşamlarını aynı sayıya çeker ve market listesini günceller"
                    : "Bu akşamın porsiyonunu kaydeder ve market listesini günceller")
            } header: {
                Text("Porsiyon")
            }

            Section("Malzemeler") {
                ForEach(recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }) { line in
                    ingredientRow(line, baseServings: recipe.baseServings)
                }
            }

            Section("Adımlar") {
                let steps = recipe.steps.sorted { $0.sortIndex < $1.sortIndex }
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.sortIndex + 1). \(step.displayText)")
                        if let minutes = step.minutes {
                            Text("\(minutes) dk")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Bunu pişirdim") {
                    viewModel.markCooked(plannedMealUUID: route.plannedMealUUID)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Section("Kaynak") {
                Text(Attribution.uniTools)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
    }

    private func ingredientKey(_ line: IngredientLine) -> String {
        "\(line.sortIndex)|\(line.ingredientId)"
    }

    private func ingredientRow(_ line: IngredientLine, baseServings: Int) -> some View {
        let quantity = PortionScaler.scale(
            quantity: line.quantity,
            scaling: line.scaling,
            baseServings: baseServings,
            householdSize: activeServings
        )
        let key = ingredientKey(line)
        let isChecked = checkedIngredientKeys.contains(key)
        let amount = QuantityFormat.quantityAndUnit(quantity: quantity, unit: line.unit)
        return Button {
            if isChecked {
                checkedIngredientKeys.remove(key)
            } else {
                checkedIngredientKeys.insert(key)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Theme.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.displayName)
                        .strikethrough(isChecked)
                        .foregroundStyle(isChecked ? .secondary : .primary)
                    Text(amount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !line.displayNote.isEmpty {
                        Text(line.displayNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(line.displayName), \(amount)")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityHint(isChecked ? "İşareti kaldırır" : "Malzemeyi işaretler")
    }

    private func portionFootnote(baseServings: Int) -> String {
        let base = max(baseServings, 1)
        let amounts = "Tarif \(base) kişilik yazılmış. Miktarlar \(activeServings) kişiye göre."
        let scope = portionContext.mealUUID == nil
            ? "Market, Porsiyonu kaydet deyince bu haftanın her akşamıyla birlikte güncellenir."
            : "Market, Porsiyonu kaydet deyince bu akşam için güncellenir. Ev halkı aynı kalır."
        return "\(amounts) \(scope)"
    }

    private func favoriteButton(isLoved: Bool) -> some View {
        Button {
            viewModel.toggleFavorite(isLoved: isLoved, slug: route.slug, in: modelContext)
        } label: {
            Label(
                isLoved ? "Favorilerde" : "Favorilere ekle",
                systemImage: isLoved ? "heart.fill" : "heart"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .accessibilityLabel(isLoved ? "Favorilerde" : "Favorilere ekle")
        .accessibilityHint(isLoved ? "Sevdiklerim listesinden çıkarır" : "Pişirmeden Sevdiklerime ekler")
    }

    private func currentRatingRow(_ rating: MealRating) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mevcut puan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(rating.title, systemImage: rating.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Mevcut puan: \(rating.title)")
                Spacer(minLength: 8)
                Button("Puanı değiştir", action: viewModel.presentRatingChange)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
