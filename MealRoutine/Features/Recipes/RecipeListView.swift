import SwiftData
import SwiftUI

struct RecipeListView: View {
    var isTabSelected: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @Query private var memories: [MealMemory]
    @Query private var prefs: [UserPrefs]
    @State private var viewModel = RecipeListViewModel()
    @State private var discovery = DiscoveryViewModel()
    @State private var allowsPhotos = false
    @State private var showsCatalog = false
    @State private var scrolledSlug: String?
    @State private var showsImport = false
    @Query(sort: \RecipeImportDraft.updatedAt, order: .reverse) private var drafts: [RecipeImportDraft]

    var body: some View {
        NavigationStack {
            Group {
                if isTabSelected && showsCatalog {
                    selectedCatalog
                } else {
                    Theme.canvas
                }
            }
            .navigationTitle("Tarifler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Tarif ekle")
                }
            }
            .sheet(isPresented: $showsImport) {
                ImportFlowView()
            }
            .navigationDestination(for: RecipeRoute.self) { route in
                RecipeDetailView(route: route, allowsCookBar: false)
            }
            .alert("Kaydedilemedi", isPresented: alertIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task(id: isTabSelected) {
            if !isTabSelected {
                showsCatalog = false
                allowsPhotos = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            showsCatalog = true
            try? await Task.sleep(for: TabSwitchTiming.settle)
            guard !Task.isCancelled else { return }
            allowsPhotos = true
            if !discoverySections.isEmpty {
                Analytics.trackOnce(.personalizedRecommendationViewed)
            }
        }
    }

    @ViewBuilder
    private var selectedCatalog: some View {
        @Bindable var viewModel = self.viewModel
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let visible = viewModel.filtered(recipes, ratings: ratings, memories: memories)
        Group {
            if recipes.isEmpty {
                    WarmEmptyState(
                        title: "Tarifler yolda",
                        message: "Katalog açılınca akşam yemekleri burada listelenir.",
                        symbolName: "book.closed",
                        accentSymbolName: "fork.knife"
                    )
                } else {
                    List {
                        Section {
                            RecipeFilterBar(
                                category: $viewModel.category,
                                cookTime: $viewModel.cookTime,
                                lovedOnly: $viewModel.lovedOnly,
                                library: $viewModel.library,
                                sort: $viewModel.sort,
                                showsClear: viewModel.hasActiveFilters,
                                onClear: viewModel.clearFilters
                            )
                            if !drafts.isEmpty {
                                Button {
                                    showsImport = true
                                } label: {
                                    Label("Taslaklar (\(drafts.count))", systemImage: "doc.text")
                                }
                            }
                        }
                        if !viewModel.hasActiveFilters {
                            PersonalizedDiscoveryView(sections: discoverySections, loadsPhoto: allowsPhotos) { slug in
                                recipes.first { $0.slug == slug }
                            }
                        }
                        if visible.isEmpty {
                            Section {
                                recipeSearchEmpty
                            }
                        } else {
                            recipeSections(visible, ratings: ratings)
                        }
                    }
                    .mealCanvas()
                    .searchable(
                        text: $viewModel.searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Tarif ara"
                    )
                    .scrollPosition(id: $scrolledSlug)
                }
        }
    }

    private var discoverySections: [DiscoverySection] {
        discovery.sections(
            recipes: recipes,
            feedback: feedback,
            memories: memories,
            prefs: prefs.min { $0.createdAt < $1.createdAt }
        )
    }

    @ViewBuilder
    private func recipeSections(_ visible: [Recipe], ratings: [String: MealRating]) -> some View {
        let showGroups = viewModel.library == .all && !viewModel.hasSearchText && viewModel.category == .all
        if showGroups {
            let imported = visible.filter { !$0.isBundledCatalog }
            let bundled = visible.filter(\.isBundledCatalog)
            if !imported.isEmpty {
                Section("İçe aktarılan tariflerin") {
                    recipeRows(imported, ratings: ratings)
                }
            }
            if !bundled.isEmpty {
                Section(viewModel.hasChipFilters ? "Sonuçlar" : "Katalog") {
                    recipeRows(bundled, ratings: ratings)
                }
            }
        } else {
            Section(viewModel.hasActiveFilters ? "Sonuçlar" : "Tüm tarifler") {
                recipeRows(visible, ratings: ratings)
            }
        }
    }

    @ViewBuilder
    private func recipeRows(_ recipes: [Recipe], ratings: [String: MealRating]) -> some View {
        ForEach(recipes, id: \.slug) { recipe in
            let memory = memories.first { $0.recipeSlug == recipe.slug }
            RecipeListRow(
                recipe: recipe,
                isLoved: ratings[recipe.slug] == .loved,
                badges: RecipeImportLabels.badges(
                    for: recipe,
                    cooked: (memory?.timesCooked ?? 0) > 0,
                    isFavorite: memory?.isFavorite == true || ratings[recipe.slug] == .loved
                ),
                loadsPhoto: allowsPhotos,
                onToggleFavorite: {
                    viewModel.toggleFavorite(
                        slug: recipe.slug,
                        isLoved: ratings[recipe.slug] == .loved,
                        in: modelContext
                    )
                }
            )
        }
    }

    private var recipeSearchEmpty: some View {
        let searching = viewModel.hasSearchText
        let filtering = viewModel.hasChipFilters
        let title = searching ? "Sonuç yok" : "Bu süzgeçte tarif yok"
        let message: String
        if searching && filtering {
            message = "Bu arama ve süzgeçle eşleşen tarif yok."
        } else if searching {
            message = "Bu aramayla eşleşen tarif yok."
        } else {
            message = "Filtreleri temizleyince bütün katalog geri gelir."
        }
        let actionTitle = searching && !filtering ? "Aramayı temizle" : "Filtreleri temizle"
        return WarmEmptyState(
            title: title,
            message: message,
            symbolName: searching ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
            accentSymbolName: "book.closed",
            actionTitle: actionTitle,
            action: { viewModel.clearFilters() },
            isCompact: true
        )
        .listRowBackground(Theme.cardSurface)
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }
}

private struct RecipeFilterBar: View {
    @Binding var category: RecipeBrowseCategory
    @Binding var cookTime: RecipeCookTimeFilter
    @Binding var lovedOnly: Bool
    @Binding var library: RecipeLibraryScope
    @Binding var sort: RecipeLibrarySort
    var showsClear: Bool
    var onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kategori")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(RecipeBrowseCategory.allCases) { item in
                    FilterChip(
                        title: item.title,
                        isSelected: category == item,
                        hint: "Kategoriye göre süzer"
                    ) {
                        category = item
                    }
                }
            }

            Text("Koleksiyon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(RecipeLibraryScope.allCases) { item in
                    FilterChip(title: item.title, isSelected: library == item, hint: "Koleksiyona göre süzer") {
                        library = item
                    }
                }
            }
            Picker("Sıralama", selection: $sort) {
                ForEach(RecipeLibrarySort.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)

            Text("Süre ve favoriler")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(RecipeCookTimeFilter.allCases) { item in
                    FilterChip(
                        title: item.title,
                        isSelected: cookTime == item,
                        accessibilityTitle: item.accessibilityTitle,
                        hint: "Pişirme süresine göre süzer"
                    ) {
                        cookTime = item
                    }
                }
                FilterChip(
                    title: "Sevdiklerim",
                    isSelected: lovedOnly,
                    hint: "Yalnızca sevdiğin tarifleri gösterir"
                ) {
                    lovedOnly.toggle()
                }
            }

            if showsClear {
                Button("Filtreleri temizle", action: onClear)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("Aramayı, kategoriyi, süreyi ve favori filtresini sıfırlar")
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecipeListRow: View {
    var recipe: Recipe
    var isLoved: Bool
    var badges: [String] = []
    var loadsPhoto: Bool
    var onToggleFavorite: () -> Void
    @State private var isPhotoShown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: RecipeRoute(slug: recipe.slug)) {
                HStack(alignment: .top, spacing: 12) {
                    RecipePhotoView(
                        urlString: recipe.photoURL,
                        author: recipe.photoAuthor,
                        license: recipe.photoLicense,
                        layout: .thumbnail,
                        loadsPhoto: loadsPhoto,
                        isPhotoShown: $isPhotoShown
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.displayName)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(recipe.timeIsUnknown ? "Süre yok" : "\(recipe.totalMinutes) dk") · \(DifficultyLabel.turkish(recipe.difficulty)) · \(RegionLabel.turkish(recipe.country))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !badges.isEmpty {
                            Text(badges.joined(separator: " · "))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isPhotoShown {
                            RecipePhotoCreditText(
                                author: recipe.photoAuthor,
                                license: recipe.photoLicense,
                                style: .compact
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint("Tarif detayını açar")

            Button(action: onToggleFavorite) {
                Image(systemName: isLoved ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(isLoved ? Theme.accent : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isLoved ? "Favorilerde" : "Favorilere ekle")
            .accessibilityHint(isLoved ? "Sevdiklerim listesinden çıkarır" : "Pişirmeden Sevdiklerime ekler")
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.card)
    }
}
