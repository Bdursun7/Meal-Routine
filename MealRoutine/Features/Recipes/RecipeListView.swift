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
        let visible = viewModel.filtered(recipes, ratings: ratings)
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
                                showsClear: viewModel.hasActiveFilters,
                                onClear: viewModel.clearFilters
                            )
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
                            Section(viewModel.hasActiveFilters ? "Sonuçlar" : "Tüm tarifler") {
                                ForEach(visible, id: \.slug) { recipe in
                                    RecipeListRow(
                                        recipe: recipe,
                                        isLoved: ratings[recipe.slug] == .loved,
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
                        Text("\(recipe.totalMinutes) dk · \(DifficultyLabel.turkish(recipe.difficulty)) · \(RegionLabel.turkish(recipe.country))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
