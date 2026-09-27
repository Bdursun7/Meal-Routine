import SwiftUI

/// Capped groups above the full catalog. Hidden while a search or chip filter is on.
struct PersonalizedDiscoveryView: View {
    var sections: [DiscoverySection]
    var loadsPhoto: Bool = true
    var recipe: (String) -> Recipe?

    var body: some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    if let recipe = recipe(item.slug) {
                        NavigationLink(value: RecipeRoute(slug: item.slug, discoverySectionID: section.id)) {
                            RecommendationCard(
                                name: recipe.displayName,
                                minutes: recipe.totalMinutes,
                                reason: item.reason,
                                badgeTitle: item.badge?.title,
                                photoURL: recipe.photoURL,
                                photoAuthor: recipe.photoAuthor,
                                photoLicense: recipe.photoLicense,
                                loadsPhoto: loadsPhoto
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint("Tarif detayını açar")
                    }
                }
            }
        }
    }
}
