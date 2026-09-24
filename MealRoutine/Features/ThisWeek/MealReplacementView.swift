import SwiftData
import SwiftUI

struct MealReplacementSheet: View {
    var mealID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var weeks: [PlanWeek]
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @Query private var prefs: [UserPrefs]
    @State private var chips: Set<ReplacementChip> = []
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        let board = ReplacementPresenter.board(
            mealID: mealID,
            chips: chips,
            weeks: weeks,
            recipes: recipes,
            feedback: feedback,
            prefs: prefs
        )
        NavigationStack {
            List {
                Section {
                    Text("Bunun yerine ne istersin?")
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if !board.currentName.isEmpty {
                        Text(board.currentName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ReplacementChip.allCases) { chip in
                                FilterChip(
                                    title: chip.title,
                                    isSelected: chips.contains(chip),
                                    hint: "Bu akşamın alternatiflerini süzer"
                                ) {
                                    chips = MealReplacement.toggled(chips, chip)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.cardSurface)
                }
                if board.choices.isEmpty {
                    Section {
                        Text("Bu filtreye uyan tarif kalmadı. Çipleri gevşet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        ForEach(board.choices) { choice in
                            Button {
                                commit(choice.slug)
                            } label: {
                                ReplacementChoiceRow(choice: choice)
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .listRowBackground(Theme.card)
                            .accessibilityLabel("\(choice.name), \(choice.minutes) dakika. \(choice.reason)")
                            .accessibilityHint("Yalnızca bu akşamın tarifini bununla değiştirir")
                        }
                    }
                }
            }
            .navigationTitle("Değiştir")
            .navigationBarTitleDisplayMode(.inline)
            .mealCanvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .accessibilityHint("Değiştirme listesini kapatır")
                }
            }
            .alert("Değiştirilemedi", isPresented: alertIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.accent)
        .mealAppearance()
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func commit(_ slug: String) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try WeekPlanService.replaceMeal(uuid: mealID, with: slug, in: modelContext)
            try GroceryListService.rebuild(in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReplacementChoiceRow: View {
    var choice: ReplacementChoicePresentation
    @State private var isPhotoShown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipePhotoView(
                urlString: choice.photoURL,
                author: choice.photoAuthor,
                license: choice.photoLicense,
                layout: .thumbnail,
                isPhotoShown: $isPhotoShown
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textCharcoal)
                    .fixedSize(horizontal: false, vertical: true)
                Label("\(choice.minutes) dk", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if !choice.reason.isEmpty {
                    Text(choice.reason)
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isPhotoShown {
                    RecipePhotoCreditText(
                        author: choice.photoAuthor,
                        license: choice.photoLicense,
                        style: .compact
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
