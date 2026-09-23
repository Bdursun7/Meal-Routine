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
                if let currentRating {
                    currentRatingRow(currentRating)
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

            Section("Malzemeler") {
                ForEach(recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.displayName)
                        Text(QuantityFormat.quantityAndUnit(quantity: line.quantity, unit: line.unit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !line.displayNote.isEmpty {
                            Text(line.displayNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
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
