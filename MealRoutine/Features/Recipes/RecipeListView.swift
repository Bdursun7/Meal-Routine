import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @State private var viewModel = RecipeListViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let visible = viewModel.filtered(recipes, ratings: ratings)
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "Tarif yok",
                        systemImage: "book.closed",
                        description: Text("Katalog henüz yüklenmedi.")
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
                        if visible.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Eşleşen tarif yok")
                                        .font(.headline)
                                    Text("Bu aramaya veya filtrelere uyan tarif yok.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button("Filtreleri temizle", action: viewModel.clearFilters)
                                        .frame(minHeight: 44)
                                }
                                .padding(.vertical, 8)
                            }
                        } else {
                            Section {
                                ForEach(visible) { recipe in
                                    RecipeListRow(
                                        recipe: recipe,
                                        isLoved: ratings[recipe.slug] == .loved,
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
                }
            }
            .navigationTitle("Tarifler")
            .navigationDestination(for: RecipeRoute.self) { route in
                RecipeDetailView(route: route)
            }
            .searchable(text: $viewModel.searchText, prompt: "Tarif ara")
            .alert("Kaydedilemedi", isPresented: alertIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
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
                    .padding(.vertical, 2)
                }
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
