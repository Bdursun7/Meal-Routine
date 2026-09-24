import SwiftUI

enum Theme {
    static let accent = Color(red: 0.769, green: 0.384, blue: 0.176)
    static let cream = Color(red: 0.984, green: 0.953, blue: 0.910)
    static let ink = Color(red: 0.227, green: 0.188, blue: 0.157)
    static let cardRadius: CGFloat = 16
}

struct FilterChip: View {
    var title: String
    var isSelected: Bool
    var accessibilityTitle: String?
    var hint: String = "Filtreyi uygular"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.accent : Theme.cream)
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityHint(isSelected ? "Seçili. \(hint)" : hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 14)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
