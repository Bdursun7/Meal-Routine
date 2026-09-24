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
                    FlowLayout(spacing: 8) {
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
                    .listRowBackground(Theme.card)
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(meta(choice))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(choice.reason)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
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

    private func meta(_ choice: ReplacementChoicePresentation) -> String {
        var parts = ["\(choice.minutes) dk"]
        if !choice.difficultyTitle.isEmpty { parts.append(choice.difficultyTitle) }
        if !choice.categoryTitle.isEmpty { parts.append(choice.categoryTitle) }
        return parts.joined(separator: " · ")
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
