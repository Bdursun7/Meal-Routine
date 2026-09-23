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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.displayName)
                                        .font(.headline)
                                    Text("\(recipe.totalMinutes) dk · \(DifficultyLabel.turkish(recipe.difficulty)) · \(RegionLabel.turkish(recipe.country))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
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
