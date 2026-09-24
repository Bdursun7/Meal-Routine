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
    @Query private var ingredientChecks: [IngredientCheck]

    let route: RecipeRoute
    @State private var viewModel = RecipeDetailViewModel()
    /// Unsaved stepper value. Nil follows the stored count for this context.
    @State private var portionDraft: Int?
    @State private var portionDraftContext: String?
    /// Last count this screen successfully wrote, so a later household save can replace it.
    @State private var lastWrittenServings: Int?
    @State private var lastWrittenContext: String?
    @State private var isHeroPhotoShown = false

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
                // Photo, then the credit strip, then the title card. Keep them stacked so the title never covers the attribution.
                VStack(alignment: .leading, spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        RecipePhotoView(
                            urlString: recipe.photoURL,
                            author: recipe.photoAuthor,
                            license: recipe.photoLicense,
                            layout: .hero,
                            isPhotoShown: $isHeroPhotoShown
                        )
                        favoriteHeart(isLoved: currentRating == .loved)
                            .padding(12)
                    }
                    recipeSummaryCard(recipe)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bgCream)
                if let currentRating {
                    currentRatingRow(currentRating)
                        .listRowBackground(Theme.cardSurface)
                }
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
                    .foregroundStyle(Theme.secondaryText)
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
                .buttonStyle(.bordered)
                .tint(Theme.accent)
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
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }

            Section {
                let cooked = isCurrentMealCooked
                Button(cooked ? "Pişirildi" : "Bunu pişirdim") {
                    viewModel.markCooked(plannedMealUUID: cookTarget?.uuid ?? route.plannedMealUUID)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cooked || viewModel.isShowingRatingPrompt)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Theme.canvas)
                .accessibilityHint(cooked ? "Bu akşam zaten pişirildi" : "Pişirme puanını sorar")
            }

            Section("Kaynak") {
                Text(Attribution.uniTools)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .mealCanvas()
    }

    /// Evening this screen cooks and shops for. A route without a meal still
    /// finds the current week's copy of the recipe, so checks reach Market.
    private var cookTarget: PlannedMeal? {
        if let mealUUID = route.plannedMealUUID {
            return plannedMeals.first { $0.uuid == mealUUID }
        }
        let start = WeekCalendar.weekStart(containing: .now)
        return plannedMeals.first { meal in
            meal.recipeSlug == route.slug
                && meal.week.map { WeekCalendar.isSameDay($0.weekStart, start) } == true
        }
    }

    private var isCurrentMealCooked: Bool {
        cookTarget?.cookedAt != nil
    }

    private func storedCheck(for line: IngredientLine) -> IngredientCheck? {
        let mealID = cookTarget?.uuid
        return ingredientChecks.first { check in
            check.ingredientId == line.ingredientId
                && check.sortIndex == line.sortIndex
                && check.recipeSlug == route.slug
                && check.mealUUID == mealID
        }
    }

    private func ingredientRow(_ line: IngredientLine, baseServings: Int) -> some View {
        let quantity = PortionScaler.scale(
            quantity: line.quantity,
            scaling: line.scaling,
            baseServings: baseServings,
            householdSize: activeServings
        )
        let stored = storedCheck(for: line)
        let isChecked = GroceryCoverage.stillCovers(
            isChecked: stored?.isChecked == true,
            coveredQuantity: stored?.coveredQuantity,
            coveredUnit: stored?.unit ?? line.unit,
            quantity: quantity,
            unit: line.unit
        )
        let amount = QuantityFormat.quantityAndUnit(quantity: quantity, unit: line.unit)
        return Button {
            viewModel.setIngredientChecked(
                isChecked: !isChecked,
                mealUUID: cookTarget?.uuid,
                recipeSlug: route.slug,
                ingredientId: line.ingredientId,
                sortIndex: line.sortIndex,
                quantity: quantity,
                unit: line.unit,
                in: modelContext
            )
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isChecked ? Theme.accent : Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.displayName)
                        .strikethrough(isChecked)
                        .foregroundStyle(isChecked ? Theme.secondaryText : Theme.textCharcoal)
                    Text(amount)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if !line.displayNote.isEmpty {
                        Text(line.displayNote)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
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

    private func recipeSummaryCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                metaChip(symbol: "clock", text: "\(recipe.totalMinutes) dk")
                metaChip(symbol: "person.2", text: "\(activeServings) kişilik")
            }
            Text("\(DifficultyLabel.turkish(recipe.difficulty)) · \(CategoryLabel.turkish(recipe.unitoolsCategory)) · \(RegionLabel.turkish(recipe.country))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.shadow, radius: 12, y: 4)
    }

    private func metaChip(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textCharcoal)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }

    private func favoriteHeart(isLoved: Bool) -> some View {
        Button {
            viewModel.toggleFavorite(isLoved: isLoved, slug: route.slug, in: modelContext)
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isLoved ? Theme.accent : Color.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(isLoved ? 0.55 : 0.38), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLoved ? "Favorilerde" : "Favorilere ekle")
        .accessibilityAddTraits(isLoved ? .isSelected : [])
        .accessibilityHint(isLoved ? "Sevdiklerim listesinden çıkarır" : "Pişirmeden Sevdiklerime ekler")
    }

    private func currentRatingRow(_ rating: MealRating) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mevcut puan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
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
