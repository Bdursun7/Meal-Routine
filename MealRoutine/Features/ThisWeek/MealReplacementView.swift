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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardGap) {
                    Text("Bunun yerine ne istersin?")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    if !board.currentName.isEmpty {
                        Text(board.currentName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
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
                    if board.choices.isEmpty {
                        Text("Bu filtreye uyan tarif kalmadı. Çipleri gevşet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(board.choices) { choice in
                                Button {
                                    commit(choice.slug)
                                } label: {
                                    ReplacementChoiceRow(choice: choice)
                                }
                                .buttonStyle(.plain)
                                .disabled(isWorking)
                                .accessibilityLabel("\(choice.name), \(choice.minutes) dakika. \(choice.reason)")
                                .accessibilityHint("Yalnızca bu akşamın tarifini bununla değiştirir")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(Theme.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bgCream)
            .navigationTitle("Değiştir")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.medium, .large])
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
        HStack(alignment: .center, spacing: 12) {
            RecipePhotoView(
                urlString: choice.photoURL,
                author: choice.photoAuthor,
                license: choice.photoLicense,
                layout: .plate,
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
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 16, y: 4)
    }
}
