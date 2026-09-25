import SwiftUI

struct MealPatternCard: View {
    var pattern: MealPattern
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pattern.message)
                .font(.body)
                .foregroundStyle(Theme.textCharcoal)
                .fixedSize(horizontal: false, vertical: true)
            Button("Bunu gizle", action: onDismiss)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHint("Bu çıkarımı gizler")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .mealCardSurface()
    }
}
