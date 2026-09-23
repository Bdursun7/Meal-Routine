import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Query private var recipes: [Recipe]
    @State private var viewModel = RecipeListViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        let visible = viewModel.filtered(recipes)
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "Tarif yok",
                        systemImage: "book.closed",
                        description: Text("Katalog henüz yüklenmedi.")
                    )
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else {
                    List {
                        ForEach(visible) { recipe in
                            NavigationLink(value: RecipeRoute(slug: recipe.slug)) {
                                RecipeListRow(recipe: recipe)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tarifler")
            .navigationDestination(for: RecipeRoute.self) { route in
                RecipeDetailView(route: route)
            }
            .searchable(text: $viewModel.searchText, prompt: "Tarif ara")
        }
    }
}

private struct RecipeListRow: View {
    var recipe: Recipe
    @State private var isPhotoShown = false

    var body: some View {
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
                Text("\(recipe.totalMinutes) dk · \(DifficultyLabel.turkish(recipe.difficulty)) · \(RegionLabel.turkish(recipe.country))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
    }
}
