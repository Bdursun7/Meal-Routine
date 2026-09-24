import SwiftData
import SwiftUI
import UIKit

/// First-run flow: welcome, the positioning line, then Ev, dislikes, a short taste sample, and a summary.
/// The week is built only from “Haftamı oluştur” on the summary.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @State private var viewModel = OnboardingViewModel()
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 40
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .welcome:
                    welcome
                case .slogan:
                    slogan
                case .household:
                    household
                case .dislikes:
                    dislikes
                case .taste:
                    taste
                case .summary:
                    summary
                }
            }
            .navigationTitle(viewModel.step.title)
            .navigationBarTitleDisplayMode(viewModel.step == .welcome || viewModel.step == .slogan ? .inline : .large)
            .toolbar(navigationVisibility, for: .navigationBar)
            .toolbar {
                if showsSetupChrome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.goBack()
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Geri")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.step.showsProgress {
                    progressHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
        .tint(Theme.accent)
        .onAppear {
            viewModel.loadChips(from: recipes)
            viewModel.trackStartIfNeeded()
        }
        .onChange(of: recipes.count) { _, _ in
            viewModel.loadChips(from: recipes)
        }
    }

    private var navigationVisibility: Visibility {
        showsSetupChrome ? .visible : .hidden
    }

    /// Welcome and the slogan are full-bleed. Setup steps keep the back button and progress.
    private var showsSetupChrome: Bool {
        switch viewModel.step {
        case .welcome, .slogan: false
        case .household, .dislikes, .taste, .summary: true
        }
    }

    /// Light cream. Dark uses the system background, not a lifted cream card.
    private var sloganBackground: Color {
        colorScheme == .dark ? Color(.systemBackground) : Theme.bgCream
    }

    private var sloganBodyColor: Color {
        colorScheme == .dark ? .primary : Theme.textCharcoal
    }

    /// Shown once, after welcome and before Ev. Copy is locked.
    private var slogan: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
                    sloganMark
                    sloganLine
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(sloganBackground.ignoresSafeArea())
    }

    /// Same artwork as the catalog app icon. The AppIcon set is not a named image, so `Image("AppIcon")` is empty on iOS.
    private var sloganMark: some View {
        Image(uiImage: AppIconMark.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityHidden(true)
    }

    private var sloganLine: some View {
        (
            Text("Diğer uygulamalar neler pişirebileceğini gösterir. ")
                .font(.title2)
                .foregroundStyle(sloganBodyColor)
            + Text("MealRoutine")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            + Text(" ise gerçekten ne pişirmek istediğini öğrenir.")
                .font(.title2)
                .foregroundStyle(sloganBodyColor)
        )
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diğer uygulamalar neler pişirebileceğini gösterir. MealRoutine ise gerçekten ne pişirmek istediğini öğrenir.")
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: heroIconSize))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Haftan, önceden planlı.")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Akşam yemeği kararını kısaltırız. Tarifler telefonunda durur.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Hesap yok, ~1 dk.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    bullet("Haftada en fazla 5 akşam", systemImage: "calendar")
                    bullet("Tek yemek Değiştir (tüm haftayı silmez)", systemImage: "arrow.triangle.2.circlepath")
                    bullet(
                        "Pişirdim + Sevdim/İdare/Asla → sonraki haftalar; market plandan birleşir",
                        systemImage: "cart"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var household: some View {
        @Bindable var viewModel = self.viewModel
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Kaç kişisiniz, haftada kaç akşam, en fazla kaç dakika?")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ev halkı")
                        .font(.headline)
                    Stepper(value: $viewModel.householdSize, in: HouseholdSizeLimits.range) {
                        Text("Ev halkı: \(viewModel.householdSize)")
                    }
                    .frame(minHeight: 44)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Akşam sayısı")
                        .font(.headline)
                    Text("Haftada kaç akşam planlayalım?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowLayout {
                        ForEach(EveningCountOptions.values, id: \.self) { count in
                            selectionChip(
                                title: EveningCountOptions.label(count),
                                isSelected: viewModel.evenings == count
                            ) {
                                viewModel.evenings = count
                            }
                        }
                    }
                    Text("Haftada en fazla 5 akşam.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("En fazla pişirme")
                        .font(.headline)
                    FlowLayout {
                        ForEach(CookTimeOptions.minutes, id: \.self) { minutes in
                            selectionChip(
                                title: CookTimeOptions.label(minutes),
                                isSelected: viewModel.maxCookMinutes == minutes
                            ) {
                                viewModel.maxCookMinutes = minutes
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var dislikes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("İşaretlediklerin bu haftanın seçimine girmez. Seçmeden de devam edebilirsin.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.chips.isEmpty {
                    Text("Malzeme listesi henüz yok.")
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout {
                        ForEach(viewModel.chips) { chip in
                            selectionChip(
                                title: chip.name,
                                isSelected: viewModel.isDisliked(chip)
                            ) {
                                viewModel.toggleDislike(chip)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var taste: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Birkaç tarife ne dersin?")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("En fazla 8 tarif. Sevdim, idare veya asla — bir kısmını işaretlemen yeter.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let sample = viewModel.sampleRecipes(from: recipes)
                if sample.isEmpty {
                    Text("Tarif listesi henüz yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sample) { recipe in
                        tasteCard(recipe)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hafta, aşağıdaki tercihlerle kurulur.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                summaryRow(title: "Ev", value: viewModel.householdSummary) {
                    viewModel.edit(.household)
                }
                summaryRow(title: "Sevmediğin malzemeler", value: viewModel.dislikeSummary) {
                    viewModel.edit(.dislikes)
                }
                summaryRow(title: "Tat", value: viewModel.tasteSummary) {
                    viewModel.edit(.taste)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if viewModel.step == .summary, let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch viewModel.step {
            case .welcome:
                Button("Kuruluma başla") {
                    viewModel.continueForward()
                }
                .buttonStyle(PrimaryButtonStyle())
            case .slogan:
                Button("Devam") {
                    viewModel.continueForward()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Devam")
            case .household, .dislikes:
                Button("Devam") {
                    viewModel.continueForward()
                }
                .buttonStyle(PrimaryButtonStyle())
            case .taste:
                Button("Devam") {
                    viewModel.continueForward()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Atla") {
                    viewModel.skipTaste()
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            case .summary:
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
        }
        .padding(.horizontal, viewModel.step == .slogan ? 24 : 16)
        .padding(.vertical, 16)
        .background {
            if viewModel.step == .slogan {
                sloganBackground.ignoresSafeArea(edges: .bottom)
            } else {
                Rectangle().fill(.bar)
            }
        }
    }

    private var progressHeader: some View {
        let index = viewModel.step.rawValue
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(index)/\(OnboardingStep.progressTotal)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Adım \(index) / \(OnboardingStep.progressTotal)")
            ProgressView(value: Double(index), total: Double(OnboardingStep.progressTotal))
                .tint(Theme.accent)
                .accessibilityHidden(true)
        }
    }

    private func bullet(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.accent : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tasteCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.displayName)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(recipe.totalMinutes) dk · \(DifficultyLabel.turkish(recipe.difficulty))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ratingButtons(for: recipe.slug)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func ratingButtons(for slug: String) -> some View {
        FlowLayout {
            ForEach(MealRating.allCases) { rating in
                let isSelected = viewModel.ratings[slug] == rating
                Button(rating.title) {
                    if isSelected {
                        viewModel.ratings[slug] = nil
                    } else {
                        viewModel.ratings[slug] = rating
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
                .buttonStyle(.bordered)
                .tint(isSelected ? Theme.accent : .secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func summaryRow(title: String, value: String, edit: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Düzenle", action: edit)
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .frame(minHeight: 44)
                .accessibilityLabel("\(title), düzenle")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// In-app named image of `AppIcon.appiconset`. The primary icon set cannot be loaded with `UIImage(named: "AppIcon")`.
private enum AppIconMark {
    static let image = UIImage(named: "AppIconMark") ?? UIImage()
}
