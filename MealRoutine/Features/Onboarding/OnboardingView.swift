import SwiftData
import SwiftUI

/// Short first-run stub: household, dislikes, optional taste seeding.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.step == 0 {
                    basics
                } else {
                    taste
                }
            }
            .navigationTitle(viewModel.step == 0 ? "Kurulum" : "Damak tadı")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
        .onAppear { viewModel.loadChips(from: recipes) }
        .onChange(of: recipes.count) { _, _ in
            viewModel.loadChips(from: recipes)
        }
    }

    private var basics: some View {
        @Bindable var viewModel = self.viewModel
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Haftan, önceden planlı.")
                        .font(.largeTitle.bold())
                    Text("Akşam yemeği kararını kısaltırız. Tarifler telefonunda durur; hesap yok.")
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $viewModel.householdSize, in: 1...8) {
                    Text("Ev halkı: \(viewModel.householdSize)")
                }
                Stepper(value: $viewModel.evenings, in: 1...NaiveMealPicker.eveningCap) {
                    Text("Akşam sayısı: \(viewModel.evenings)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("En fazla pişirme")
                        .font(.headline)
                    Picker("En fazla pişirme", selection: $viewModel.maxCookMinutes) {
                        ForEach(CookTimeOptions.minutes, id: \.self) { minutes in
                            Text("\(minutes) dk").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sevmediğin malzemeler")
                        .font(.headline)
                    Text("İşaretlediklerin bu haftanın seçimine girmez.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(viewModel.chips) { chip in
                            dislikeChip(chip)
                        }
                    }
                }

                Button("Devam") {
                    viewModel.step = 1
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
    }

    private var taste: some View {
        List {
            Section {
                Text("İstersen 20 tariften birini işaretle. Boş bırakırsan skor sırasıyla seçeriz. Adımlar şimdilik İngilizce.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(viewModel.sampleRecipes(from: recipes)) { recipe in
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.displayName)
                        .font(.headline)
                    Text("\(recipe.totalMinutes) dk · \(DifficultyLabel.turkish(recipe.difficulty))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ratingButtons(for: recipe.slug)
                }
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    viewModel.finish(in: modelContext)
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Haftamı oluştur")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isSaving)
            }
            .padding(16)
            .background(.bar)
        }
    }

    private func dislikeChip(_ chip: IngredientChip) -> some View {
        let isSelected = viewModel.disliked.contains(chip.id)
        return Button {
            viewModel.toggleDislike(chip.id)
        } label: {
            Text(chip.name)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func ratingButtons(for slug: String) -> some View {
        HStack(spacing: 8) {
            ForEach(MealRating.allCases) { rating in
                let isSelected = viewModel.ratings[slug] == rating
                Button(rating.title) {
                    if isSelected {
                        viewModel.ratings[slug] = nil
                    } else {
                        viewModel.ratings[slug] = rating
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(isSelected ? Theme.accent : .secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
