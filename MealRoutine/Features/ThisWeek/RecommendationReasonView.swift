import SwiftUI

/// One-line reason under a meal or a discovery row.
struct RecommendationReasonView: View {
    var text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FamiliarityBadgeLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(title == FamiliarityBadge.new.title ? Theme.accent : Theme.sage)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}
