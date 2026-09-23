import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]

    let route: RecipeRoute
    @State private var viewModel = RecipeDetailViewModel()

    private var recipe: Recipe? {
        recipes.first { $0.slug == route.slug }
    }

    var body: some View {
        @Bindable var viewModel = self.viewModel
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
        .confirmationDialog(
            "Bu yemek nasıldı?",
            isPresented: $viewModel.isShowingFeedback,
            titleVisibility: .visible
        ) {
            Button("Sevdim") { viewModel.commit(rating: .loved, slug: route.slug, in: modelContext) }
            Button("İdare eder") { viewModel.commit(rating: .okay, slug: route.slug, in: modelContext) }
            Button("Bir daha asla", role: .destructive) {
                viewModel.commit(rating: .never, slug: route.slug, in: modelContext)
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .alert(
            "Kaydedilemedi",
            isPresented: alertIsPresented
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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

    @ViewBuilder
    private func content(_ recipe: Recipe) -> some View {
        let latest = FeedbackIndex.latestRatings(in: feedback)[recipe.slug]
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.displayName)
                            .font(.title2.bold())
                        Text("\(recipe.totalMinutes) dk · \(recipe.baseServings) kişilik taban")
                            .foregroundStyle(.secondary)
                        Text("\(DifficultyLabel.turkish(recipe.difficulty)) · \(CategoryLabel.turkish(recipe.unitoolsCategory)) · \(RegionLabel.turkish(recipe.country))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if let latest {
                    Label(latest.title, systemImage: latest.systemImage)
                }
                Text("Pişirme adımları V1'de İngilizce.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !recipe.summaryEN.isEmpty {
                Section("Özet (İngilizce)") {
                    Text(recipe.summaryEN)
                }
            }

            if !recipe.diets.isEmpty {
                Section("Beslenme") {
                    Text(recipe.diets.map(DietLabel.turkish).joined(separator: " · "))
                }
            }

            Section("Malzemeler") {
                ForEach(recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.displayName)
                        Text(QuantityFormat.quantityAndUnit(quantity: line.quantity, unit: line.unit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !line.note.isEmpty {
                            Text(line.note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Adımlar (İngilizce)") {
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
                    viewModel.markCooked(
                        slug: recipe.slug,
                        plannedMealUUID: route.plannedMealUUID,
                        in: modelContext
                    )
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
}
