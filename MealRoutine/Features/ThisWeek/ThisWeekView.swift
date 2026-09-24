import SwiftData
import SwiftUI

struct ThisWeekView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Query private var weeks: [PlanWeek]
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @Query private var prefs: [UserPrefs]
    @State private var viewModel = ThisWeekViewModel()
    @State private var replacingMeal: ReplacingMeal?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var householdSize: Int {
        let stored = prefs.min { $0.createdAt < $1.createdAt }?.householdSize ?? 2
        return HouseholdSizeLimits.clamped(stored)
    }

    var body: some View {
        let meals = viewModel.meals(
            weeks: weeks,
            recipes: recipes,
            feedback: feedback,
            householdSize: householdSize
        )
        let summary = viewModel.summary(meals: meals)
        let featured = viewModel.featuredEvening(in: meals)

        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("Bu hafta boş", systemImage: "calendar")
                    } description: {
                        Text("Filtrelere uyan tarif çıkmadı. Profil'den süre sınırını yükselt veya sevmediğin malzemeleri azalt.")
                    } actions: {
                        Button("Planı yeniden kur") {
                            viewModel.regenerate(in: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            progressCard(summary)
                            if let featured {
                                TonightDinnerCard(
                                    meal: featured,
                                    recipe: recipes.first { $0.slug == featured.slug },
                                    title: viewModel.featuredEveningTitle(for: featured),
                                    isWorking: viewModel.isWorking,
                                    onReplace: { replacingMeal = ReplacingMeal(id: featured.id) }
                                )
                            }
                            if let insight = viewModel.preferenceInsight(recipes: recipes, feedback: feedback) {
                                insightCard(insight)
                            }
                            Text("Haftanın akşamları")
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                                .padding(.top, 4)
                            ForEach(meals) { meal in
                                WeekMealCard(
                                    meal: meal,
                                    recipe: recipes.first { $0.slug == meal.slug },
                                    isWorking: viewModel.isWorking,
                                    onReplace: { replacingMeal = ReplacingMeal(id: meal.id) }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .background(Theme.canvas)
                }
            }
            .navigationTitle("Bu Hafta")
            .background(Theme.canvas)
            .navigationDestination(for: RecipeRoute.self) { route in
                RecipeDetailView(route: route)
            }
            .sheet(item: $replacingMeal) { meal in
                MealReplacementSheet(mealID: meal.id)
            }
            .alert(
                "İşlem tamamlanamadı",
                isPresented: alertIsPresented
            ) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
        }
        .onAppear {
            viewModel.ensureWeek(in: modelContext)
            Analytics.track(.planViewed)
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.alertMessage = nil }
            }
        )
    }

    private func progressCard(_ summary: WeekSummaryPresentation) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    WeekProgressRing(cooked: summary.cooked, planned: summary.planned)
                    progressCopy(summary)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    WeekProgressRing(cooked: summary.cooked, planned: summary.planned)
                    progressCopy(summary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .mealCardSurface(fill: Theme.bgCream)
        .accessibilityElement(children: .contain)
    }

    private func progressCopy(_ summary: WeekSummaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Haftalık ilerleme")
                .font(.headline)
                .foregroundStyle(Theme.textCharcoal)
            Text("\(summary.cooked)/\(summary.planned) yemek pişirildi")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            ThinSageProgress(value: Double(summary.cooked), total: Double(max(summary.planned, 1)))
            if summary.loved > 0 {
                Text("\(summary.loved) sevildi")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                selectedTab = .grocery
            } label: {
                Label("Market listesi", systemImage: "cart")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityHint("Market sekmesini açar")
        }
    }

    private func insightCard(_ insight: PreferenceInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(insight.title, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(insight.message)
                .font(.body)
                .foregroundStyle(Theme.textCharcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .mealCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.title). \(insight.message)")
    }

}

private struct ReplacingMeal: Identifiable {
    var id: UUID
}

private struct AdaptiveActions<First: View, Second: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                first()
                second()
            }
        } else {
            HStack(spacing: 8) {
                first()
                second()
            }
        }
    }
}

private struct WeekMealCard: View {
    var meal: WeekMealPresentation
    var recipe: Recipe?
    var isWorking: Bool
    var onReplace: () -> Void
    @State private var isPhotoShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.dayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(meal.dateTitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if meal.isCooked {
                    CookedMark()
                }
            }

            NavigationLink(value: RecipeRoute(slug: meal.slug, plannedMealUUID: meal.id)) {
                HStack(alignment: .top, spacing: 12) {
                    RecipePhotoView(
                        urlString: recipe?.photoURL ?? "",
                        author: recipe?.photoAuthor ?? "",
                        license: recipe?.photoLicense ?? "",
                        layout: .thumbnail,
                        isPhotoShown: $isPhotoShown
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.recipeName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textCharcoal)
                        Text("\(meal.minutes) dk · \(meal.servings) kişilik")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        if let rating = meal.rating {
                            Label(rating.title, systemImage: rating.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if isPhotoShown {
                            RecipePhotoCreditText(
                                author: recipe?.photoAuthor ?? "",
                                license: recipe?.photoLicense ?? "",
                                style: .compact
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button("Değiştir") {
                onReplace()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: Theme.chipRadius))
            .tint(Theme.accent)
            .frame(minHeight: 44)
            .disabled(isWorking)
            .accessibilityLabel("Değiştir")
            .accessibilityHint("Bu akşam için alternatif tarifleri açar")
        }
        .padding(16)
        .mealCardSurface()
    }
}

private struct WeekProgressRing: View {
    var cooked: Int
    var planned: Int
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 76

    private var fraction: Double {
        guard planned > 0 else { return 0 }
        return min(1, Double(cooked) / Double(planned))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.sage.opacity(0.22), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.sage, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(cooked)/\(planned)")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
        .frame(width: min(side, 112), height: min(side, 112))
        .accessibilityHidden(true)
    }
}

private struct CookedMark: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.sage)
                .accessibilityHidden(true)
            Text("Pişti")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textCharcoal)
        }
    }
}

private struct TonightDinnerCard: View {
    var meal: WeekMealPresentation
    var recipe: Recipe?
    var title: String
    var isWorking: Bool
    var onReplace: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPhotoShown = false

    private var timeLabel: String {
        meal.difficultyTitle.isEmpty
            ? "\(meal.minutes) dk"
            : "\(meal.minutes) dk · \(meal.difficultyTitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    tonightMark
                    tonightCopy
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    tonightMark
                    tonightCopy
                }
            }

            if isPhotoShown {
                RecipePhotoCreditText(
                    author: recipe?.photoAuthor ?? "",
                    license: recipe?.photoLicense ?? "",
                    style: .compact
                )
                .foregroundStyle(Color.white.opacity(0.8))
            }

            AdaptiveActions {
                NavigationLink(value: RecipeRoute(slug: meal.slug, plannedMealUUID: meal.id)) {
                    Text("Tarifi aç")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tarifi aç")
                .accessibilityHint("\(meal.recipeName) tarifini açar")
            } second: {
                Button("Değiştir", action: onReplace)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.clear)
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                    }
                    .disabled(isWorking)
                    .accessibilityLabel("Değiştir")
                    .accessibilityHint("Bu akşam için alternatif tarifleri açar")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.shadow, radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var tonightMark: some View {
        let hasPhoto = RecipePhoto.remoteURL(from: recipe?.photoURL ?? "") != nil
        if hasPhoto {
            RecipePhotoView(
                urlString: recipe?.photoURL ?? "",
                author: recipe?.photoAuthor ?? "",
                license: recipe?.photoLicense ?? "",
                layout: .thumbnail,
                isPhotoShown: $isPhotoShown
            )
        } else {
            Image(systemName: "fork.knife")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var tonightCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(meal.recipeName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Label(timeLabel, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.9))
            Text(meal.isToday ? meal.dayTitle : "\(meal.dayTitle) · \(meal.dateTitle)")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.8))
            if meal.isCooked {
                Label("Pişti", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(meal.recipeName). \(timeLabel)")
    }
}
