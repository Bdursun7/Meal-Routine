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
                    WarmEmptyState(
                        title: "Bu hafta henüz kurulmadı",
                        message: "Akşamlarını birlikte seçelim. Süre sınırını yükseltmek veya sevmediğin malzemeleri azaltmak yeni tarifler açar.",
                        symbolName: "calendar",
                        accentSymbolName: "fork.knife",
                        actionTitle: "Planı yeniden kur",
                        action: { viewModel.regenerate(in: modelContext) }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.sectionGap) {
                            VStack(alignment: .leading, spacing: Theme.cardGap) {
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
                            }
                            VStack(alignment: .leading, spacing: Theme.cardGap) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Haftanın akşamları")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Theme.textCharcoal)
                                    Text("Her akşam kendi kartında")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .accessibilityElement(children: .combine)
                                ForEach(meals) { meal in
                                    WeekMealCard(
                                        meal: meal,
                                        recipe: recipes.first { $0.slug == meal.slug },
                                        isWorking: viewModel.isWorking,
                                        onReplace: { replacingMeal = ReplacingMeal(id: meal.id) }
                                    )
                                }
                            }
                        }
                        .padding(Theme.screenPadding)
                    }
                    .background(Theme.canvas)
                }
            }
            .navigationTitle("Bu Hafta")
            .background(Theme.canvas)
            .navigationDestination(for: RecipeRoute.self) { route in
                RecipeDetailView(route: route, allowsCookBar: true)
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
        .mealCardSurface(fill: Theme.cardSurface)
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
            Text("Pişen akşamlar burada birikir.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ThinSageProgress(value: Double(summary.cooked), total: Double(max(summary.planned, 1)), height: 8)
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
            .tint(Theme.sage)
            .accessibilityHint("Market sekmesini açar")
        }
    }

    private func insightCard(_ insight: PreferenceInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(insight.title, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.sage)
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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.dayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: Capsule())
                    Text(meal.dateTitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                if meal.isCooked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.sage)
                        .accessibilityLabel("Pişti")
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
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
            .tint(Theme.sage)
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
                .stroke(Theme.sage.opacity(0.22), lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.sage, style: StrokeStyle(lineWidth: 10, lineCap: .round))
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

private struct TonightDinnerCard: View {
    var meal: WeekMealPresentation
    var recipe: Recipe?
    var title: String
    var isWorking: Bool
    var onReplace: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPhotoShown = false

    private var hasRemotePhoto: Bool {
        RecipePhoto.remoteURL(from: recipe?.photoURL ?? "") != nil
    }

    /// White sits on the photo scrim. The orange fill needs dark green type.
    private var heroInk: Color {
        hasRemotePhoto ? .white : Theme.onAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize || !hasRemotePhoto {
                    HStack(alignment: .center, spacing: 14) {
                        if !hasRemotePhoto { symbolStack }
                        tonightCopy
                    }
                } else {
                    tonightCopy
                }
                AdaptiveActions {
                    NavigationLink(value: RecipeRoute(slug: meal.slug, plannedMealUUID: meal.id)) {
                        Text("Tarifi aç")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onAccent)
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
                        .foregroundStyle(heroInk)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.clear)
                        .buttonStyle(.plain)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                                .strokeBorder(heroInk.opacity(0.9), lineWidth: 1.5)
                        }
                        .disabled(isWorking)
                        .accessibilityLabel("Değiştir")
                        .accessibilityHint("Bu akşam için alternatif tarifleri açar")
                }
            }
            .padding(Theme.screenPadding)
            .padding(.top, hasRemotePhoto ? 28 : 0)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .bottomLeading)
        .background {
            ZStack {
                if hasRemotePhoto {
                    RecipePhotoView(
                        urlString: recipe?.photoURL ?? "",
                        author: recipe?.photoAuthor ?? "",
                        license: recipe?.photoLicense ?? "",
                        layout: .backdrop,
                        isPhotoShown: $isPhotoShown
                    )
                    Theme.scrimTop
                    Theme.scrimBottom
                } else {
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if isPhotoShown, let credit = RecipePhoto.creditLine(
                author: recipe?.photoAuthor ?? "",
                license: recipe?.photoLicense ?? ""
            ) {
                Text("Fotoğraf: \(credit)")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
                    .padding(14)
                    .padding(.trailing, 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.heroCorner, style: .continuous))
        .shadow(color: Theme.elevatedShadow, radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var symbolStack: some View {
        ZStack {
            Circle()
                .fill(Theme.onAccent.opacity(0.12))
                .frame(width: 88, height: 88)
            Circle()
                .fill(Theme.sage.opacity(0.55))
                .frame(width: 36, height: 36)
                .offset(x: 28, y: -22)
            Image(systemName: "fork.knife")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
            Image(systemName: "leaf.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.onAccent.opacity(0.9))
                .offset(x: 28, y: -22)
        }
        .accessibilityHidden(true)
    }

    private var tonightCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(heroInk.opacity(0.9))
            Text(meal.recipeName)
                .font(.title2.bold())
                .foregroundStyle(heroInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("\(meal.minutes) dk", systemImage: "clock")
                Text("\(meal.servings) kişilik")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(heroInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(heroInk.opacity(0.12), in: Capsule())
            if meal.isCooked {
                Label("Pişti", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(heroInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(meal.recipeName). \(meal.minutes) dakika. \(meal.servings) kişilik")
    }
}
