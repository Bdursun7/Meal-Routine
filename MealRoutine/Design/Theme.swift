import SwiftUI
import UIKit

/// Warm terracotta, cream, and sage tokens. Light values follow the moodboard.
/// Dark values stay warm and lifted so text, chips, and cards keep contrast.
enum Theme {
    static let accent = adaptive(
        light: UIColor(red: 0.769, green: 0.384, blue: 0.176, alpha: 1),
        dark: UIColor(red: 0.70, green: 0.36, blue: 0.20, alpha: 1)
    )
    static let onAccent = Color.white
    static let cream = adaptive(
        light: UIColor(red: 0.984, green: 0.953, blue: 0.910, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.19, blue: 0.16, alpha: 1)
    )
    static let canvas = adaptive(
        light: UIColor(red: 0.965, green: 0.937, blue: 0.890, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.098, blue: 0.086, alpha: 1)
    )
    static let card = adaptive(
        light: UIColor(red: 0.996, green: 0.984, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.18, green: 0.155, blue: 0.133, alpha: 1)
    )
    static let ink = adaptive(
        light: UIColor(red: 0.227, green: 0.188, blue: 0.157, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.93, blue: 0.89, alpha: 1)
    )
    static let sage = adaptive(
        light: UIColor(red: 0.29, green: 0.43, blue: 0.30, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.76, blue: 0.58, alpha: 1)
    )
    static let shadow = adaptive(
        light: UIColor(white: 0, alpha: 0.08),
        dark: UIColor(white: 0, alpha: 0.28)
    )
    static let cardRadius: CGFloat = 18

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// Persisted light, dark, or system appearance. Applied from the app root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "mealroutine.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }

    var preferredScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct MealAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.preferredScheme)
    }
}

extension View {
    func mealCardSurface() -> some View {
        background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: Theme.shadow, radius: 10, y: 4)
    }

    func mealCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
    }

    /// Sheets do not always inherit the root color scheme, so presented screens apply it too.
    func mealAppearance() -> some View {
        modifier(MealAppearanceModifier())
    }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(isSelected ? Theme.accent : Theme.cream)
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Theme.accent.opacity(0.35),
                            lineWidth: 1
                        )
                }
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
            .foregroundStyle(Theme.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: Theme.accent.opacity(isEnabled && !configuration.isPressed ? 0.22 : 0), radius: 8, y: 4)
            .opacity(isEnabled ? 1 : 0.45)
    }
}
