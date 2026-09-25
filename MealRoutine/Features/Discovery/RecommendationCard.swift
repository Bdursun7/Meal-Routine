import SwiftUI

struct RecommendationCard: View {
    var name: String
    var minutes: Int
    var reason: String
    var badgeTitle: String?
    var photoURL: String
    var photoAuthor: String
    var photoLicense: String

    @State private var isPhotoShown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipePhotoView(
                urlString: photoURL,
                author: photoAuthor,
                license: photoLicense,
                layout: .thumbnail,
                isPhotoShown: $isPhotoShown
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(Theme.textCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badgeTitle {
                        FamiliarityBadgeLabel(title: badgeTitle)
                    }
                }
                Text("\(minutes) dk")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                RecommendationReasonView(text: reason)
                if isPhotoShown {
                    RecipePhotoCreditText(
                        author: photoAuthor,
                        license: photoLicense,
                        style: .compact
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(minutes) dakika. \(reason)")
    }
}
