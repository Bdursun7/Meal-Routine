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
                                tonightCard(featured)
                            }
                            if let insight = viewModel.preferenceInsight(recipes: recipes, feedback: feedback) {
                                insightCard(insight)
                            }
                            Text("Haftanın akşamları")
                                .font(.headline)
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
                }
            }
            .navigationTitle("Bu Hafta")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Haftalık ilerleme")
                .font(.headline)
            Text("\(summary.cooked)/\(summary.planned) yemek pişirildi")
                .font(.title3.weight(.semibold))
            ProgressView(value: Double(summary.cooked), total: Double(max(summary.planned, 1)))
                .tint(Theme.accent)
            if summary.loved > 0 {
                Text("\(summary.loved) sevildi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func tonightCard(_ meal: WeekMealPresentation) -> some View {
        let meta = meal.difficultyTitle.isEmpty
            ? "\(meal.minutes) dk"
            : "\(meal.minutes) dk · \(meal.difficultyTitle)"
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.featuredEveningTitle(for: meal))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text(meal.isToday ? meal.dayTitle : "\(meal.dayTitle) · \(meal.dateTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(meal.recipeName)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if meal.isCooked {
                    Label("Pişti", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.featuredEveningTitle(for: meal)). \(meal.recipeName). \(meta)")

            AdaptiveActions {
                NavigationLink(value: RecipeRoute(slug: meal.slug, plannedMealUUID: meal.id)) {
                    Text("Tarifi aç")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityLabel("Tarifi aç")
                .accessibilityHint("\(meal.recipeName) tarifini açar")
            } second: {
                Button("Değiştir") {
                    replacingMeal = ReplacingMeal(id: meal.id)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(viewModel.isWorking)
                .accessibilityLabel("Değiştir")
                .accessibilityHint("Bu akşam için alternatif tarifleri açar")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func insightCard(_ insight: PreferenceInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(insight.title, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(insight.message)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if meal.isCooked {
                    Label("Pişti", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
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
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(meal.minutes) dk · \(meal.servings) kişilik")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
            .frame(minHeight: 44)
            .disabled(isWorking)
            .accessibilityLabel("Değiştir")
            .accessibilityHint("Bu akşam için alternatif tarifleri açar")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}
