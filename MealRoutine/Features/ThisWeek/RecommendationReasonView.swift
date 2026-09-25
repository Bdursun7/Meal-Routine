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
    /// Hero photos need a solid capsule. Cream cards use a light tint of the same color.
    var onDarkBackground = false

    private var isNew: Bool { title == FamiliarityBadge.new.title }
    private var tint: Color { isNew ? Theme.accent : Theme.sage }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(onDarkBackground ? Color.white : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(onDarkBackground ? tint : tint.opacity(0.18), in: Capsule())
            .accessibilityLabel(title)
    }
}
