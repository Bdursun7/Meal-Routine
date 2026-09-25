import SwiftData
import SwiftUI

/// Recent behavior rows. Cook bar stays off; this is history, not Bu Hafta.
struct MealHistoryView: View {
    @Query(sort: \MealBehaviorEvent.createdAt, order: .reverse) private var events: [MealBehaviorEvent]
    @Query private var recipes: [Recipe]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("Henüz kayıt yok", systemImage: "clock")
                } description: {
                    Text("Pişirme, değiştirme ve puanlar burada birikir.")
                }
            } else {
                List(Array(events.prefix(40)), id: \.uuid) { event in
                    NavigationLink {
                        RecipeDetailView(route: RecipeRoute(slug: event.recipeSlug), allowsCookBar: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name(event.recipeSlug))
                                .font(.headline)
                                .foregroundStyle(Theme.textCharcoal)
                            Text("\(title(event.eventType)) · \(Self.mediumDate(event.createdAt))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hafıza günlüğü")
        .navigationBarTitleDisplayMode(.inline)
        .mealCanvas()
    }

    private func name(_ slug: String) -> String {
        recipes.first { $0.slug == slug }?.displayName ?? slug
    }

    private static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func title(_ event: MealBehaviorEventType) -> String {
        switch event {
        case .viewed: "Görüldü"
        case .selected: "Plana alındı"
        case .cooked: "Pişirildi"
        case .replaced: "Değiştirildi"
        case .skipped: "Atlandı"
        case .loved: "Sevildi"
        case .okay: "İdare eder"
        case .neverAgain: "Bir daha asla"
        case .favorited: "Favorilere eklendi"
        }
    }
}
