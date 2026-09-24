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
    /// Only Bu Hafta passes true. Tarifler and Profil leave this false, so the cook bar is never built.
    var allowsCookBar = false
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
        attachAlerts(noticeBehavior(navigationChrome(detailRoot)))
    }

    @ViewBuilder
    private var detailRoot: some View {
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

    private func navigationChrome<Content: View>(_ root: Content) -> some View {
        root
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbarBackground(Theme.bgCream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(content: favoriteToolbar)
            .overlay { ratingOverlay }
    }

    @ToolbarContentBuilder
    private func favoriteToolbar() -> some ToolbarContent {
        if recipe != nil {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteHeart(isLoved: currentRating == .loved)
            }
        }
    }

    private var ratingOverlay: some View {
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

    private func noticeBehavior<Content: View>(_ root: Content) -> some View {
        root
            .sensoryFeedback(.success, trigger: viewModel.savedNotice?.id) { _, newValue in
                newValue != nil
            }
            .onChange(of: viewModel.savedNotice?.id) { _, newID in
                announceSavedNotice(newID)
            }
            .task(id: viewModel.savedNotice?.id) {
                await dismissSavedNoticeAfterDelay()
            }
            .onAppear {
                Analytics.track(.recipeOpened)
            }
            .onChange(of: portionContext) { _, newContext in
                clearPortionDraftIfSaved(newContext)
            }
    }

    private func attachAlerts<Content: View>(_ root: Content) -> some View {
        root
            .alert("Kaydedilemedi", isPresented: alertIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Kaydedildi", isPresented: portionStatusIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.portionStatusMessage ?? "")
            }
    }

    private func announceSavedNotice(_ newID: UUID?) {
        guard newID != nil, let notice = viewModel.savedNotice else { return }
        AccessibilityNotification.Announcement(notice.message).post()
    }

    private func dismissSavedNoticeAfterDelay() async {
        guard viewModel.savedNotice != nil else { return }
        try? await Task.sleep(for: .seconds(3.2))
        guard !Task.isCancelled else { return }
        viewModel.dismissSavedNotice()
    }

    private func clearPortionDraftIfSaved(_ newContext: PortionContext) {
        let draftMatchesWrite = portionDraft == lastWrittenServings || portionDraft == newContext.persisted
        guard portionDraftContext == newContext.contextID,
              lastWrittenContext == newContext.contextID,
              draftMatchesWrite
        else { return }
        portionDraft = nil
        portionDraftContext = nil
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

    /// The evening opened from Bu Hafta, and only if it still belongs to this week.
    /// A previous week's cooked copy of the same recipe does not count.
    private var currentWeekCookMeal: PlannedMeal? {
        guard allowsCookBar, let mealUUID = route.plannedMealUUID else { return nil }
        let start = WeekCalendar.weekStart(containing: .now)
        return plannedMeals.first { meal in
            meal.uuid == mealUUID
                && meal.week.map { WeekCalendar.isSameDay($0.weekStart, start) } == true
        }
    }

    private var showsCookAction: Bool {
        currentWeekCookMeal != nil
    }

    @ViewBuilder
    private func content(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            recipeList(recipe)
                .layoutPriority(1)
            if showsCookAction {
                cookBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bgCream)
    }

    private func recipeList(_ recipe: Recipe) -> some View {
        List {
            heroSection(recipe)
            summarySection(recipe)
            dietSection(recipe)
            portionSection(recipe)
            ingredientSection(recipe)
            stepsSection(recipe)
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .mealCanvas()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroSection(_ recipe: Recipe) -> some View {
        Section {
            recipeHero(recipe)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bgCream)
            if let currentRating {
                currentRatingRow(currentRating)
                    .recipeDetailRow()
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ recipe: Recipe) -> some View {
        if !recipe.displaySummary.isEmpty {
            Section("Özet") {
                Text(recipe.displaySummary)
                    .recipeDetailRow()
            }
        }
    }

    @ViewBuilder
    private func dietSection(_ recipe: Recipe) -> some View {
        if !recipe.diets.isEmpty {
            Section("Beslenme") {
                Text(recipe.diets.map(DietLabel.turkish).joined(separator: " · "))
                    .recipeDetailRow()
            }
        }
    }

    private func portionSection(_ recipe: Recipe) -> some View {
        Section {
            portionStepper
            Text(portionFootnote(baseServings: recipe.baseServings))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .recipeDetailRow()
            savePortionButton
        } header: {
            Text("Porsiyon")
        }
    }

    private var portionStepper: some View {
        Stepper(value: servingsBinding, in: HouseholdSizeLimits.range) {
            Text(portionContext.mealUUID == nil
                 ? "Ev halkı: \(activeServings) kişi"
                 : "Bu akşam: \(activeServings) kişi")
        }
        .accessibilityLabel("Porsiyon \(activeServings) kişi")
        .recipeDetailRow()
    }

    private var savePortionButton: some View {
        Button("Porsiyonu kaydet", action: savePortionDraft)
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityHint(portionContext.mealUUID == nil
                ? "Ev halkını kaydeder, bu haftanın akşamlarını aynı sayıya çeker ve market listesini günceller"
                : "Bu akşamın porsiyonunu kaydeder ve market listesini günceller")
            .recipeDetailRow()
    }

    private func savePortionDraft() {
        let saved = activeServings
        let contextID = portionContext.contextID
        viewModel.savePortions(
            servings: saved,
            mealUUID: portionContext.mealUUID,
            in: modelContext
        )
        guard viewModel.errorMessage == nil else { return }
        lastWrittenContext = contextID
        lastWrittenServings = saved
        portionDraftContext = contextID
        portionDraft = saved
    }

    private func ingredientSection(_ recipe: Recipe) -> some View {
        Section("Malzemeler") {
            ForEach(recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }) { line in
                ingredientRow(line, baseServings: recipe.baseServings)
                    .recipeDetailRow()
            }
        }
    }

    private func stepsSection(_ recipe: Recipe) -> some View {
        let steps = recipe.steps.sorted { $0.sortIndex < $1.sortIndex }
        return Section("Adımlar") {
            ForEach(steps) { step in
                stepRow(step)
            }
        }
    }

    private func stepRow(_ step: RecipeStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(step.sortIndex + 1). \(step.displayText)")
            if let minutes = step.minutes {
                Text("\(minutes) dk")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .recipeDetailRow()
    }

    /// Docked under the list, above the tab bar. The list scrolls in the space above it.
    private var cookBar: some View {
        VStack(spacing: 8) {
            if let notice = viewModel.savedNotice {
                SavedRatingToast(notice: notice, onDismiss: viewModel.dismissSavedNotice)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            let cooked = isCurrentMealCooked
            Button(cooked ? "Pişirildi" : "Bunu pişirdim") {
                viewModel.markCooked(plannedMealUUID: currentWeekCookMeal?.uuid)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(cooked || viewModel.isShowingRatingPrompt)
            .accessibilityHint(cooked ? "Bu akşam zaten pişirildi" : "Pişirme puanını sorar")
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.bgCream)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.textCharcoal.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.savedNotice?.id)
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
        currentWeekCookMeal?.cookedAt != nil
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
                MealCheckBox(isChecked: isChecked)
                    .frame(minWidth: 44, minHeight: 44)
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
        .sensoryFeedback(.selection, trigger: isChecked)
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

    /// Photo, then the credit, then the title card. Nothing overlaps.
    private func recipeHero(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RecipePhotoView(
                urlString: recipe.photoURL,
                author: recipe.photoAuthor,
                license: recipe.photoLicense,
                layout: .hero,
                isPhotoShown: $isHeroPhotoShown
            )
            heroCredit(recipe)
                .padding(.horizontal, Theme.screenPadding)
            recipeSummaryCard(recipe)
                .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.bottom, 8)
    }

    private func heroCredit(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isHeroPhotoShown, let credit = RecipePhoto.creditLine(author: recipe.photoAuthor, license: recipe.photoLicense) {
                Text("Fotoğraf: \(credit)")
            }
            Text(Attribution.uniTools)
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private func recipeSummaryCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.displayName)
                .font(.title2.bold())
                .foregroundStyle(Theme.textCharcoal)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            RecipeMetaChips(
                minutes: recipe.totalMinutes,
                servings: activeServings,
                difficulty: DifficultyLabel.turkish(recipe.difficulty)
            )
            Text("\(CategoryLabel.turkish(recipe.unitoolsCategory)) · \(RegionLabel.turkish(recipe.country))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func favoriteHeart(isLoved: Bool) -> some View {
        Button {
            viewModel.toggleFavorite(isLoved: isLoved, slug: route.slug, in: modelContext)
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(isLoved ? Theme.accent : Theme.textCharcoal)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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

/// Icon and label on one line. Fixed size so a list row cannot stretch these into empty towers.
private struct RecipeMetaChips: View {
    var minutes: Int
    var servings: Int
    var difficulty: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                timeChip
                servingsChip
                difficultyChip
            }
            .fixedSize(horizontal: true, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    timeChip
                    servingsChip
                }
                difficultyChip
            }
            VStack(alignment: .leading, spacing: 8) {
                timeChip
                servingsChip
                difficultyChip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeChip: some View {
        chip(symbol: "clock", text: "\(minutes) dk")
    }

    private var servingsChip: some View {
        chip(symbol: "person.2", text: "\(servings) kişilik")
    }

    private var difficultyChip: some View {
        chip(symbol: "chart.bar", text: difficulty)
    }

    private func chip(symbol: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textCharcoal)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .fixedSize(horizontal: true, vertical: true)
    }
}

private extension View {
    /// Body row on the cream page. The hero does not use this, so the photo stays full width.
    func recipeDetailRow() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Theme.cardSurface)
            .listRowSeparator(.hidden)
    }
}
