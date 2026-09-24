import SwiftUI
import UIKit

/// Warm terracotta, cream, and sage tokens.
/// Light values follow the moodboard. Dark values are a lifted cream, not pure black.
/// Accent stays the existing terracotta in both modes.
enum Theme {
    /// Existing terracotta, #C4622D. CTA, tab tint, Tonight fill, selected chip.
    static let accent = Color(red: 0.769, green: 0.384, blue: 0.176)
    static let primary = accent
    static let onAccent = Color.white

    /// Screen background. #F8F4ED in light.
    static let bgCream = adaptive(
        light: ui(0xF8F4ED),
        dark: ui(0x1C1916)
    )
    static let canvas = bgCream
    static let cream = bgCream

    /// Slightly lighter than the cream canvas. #FFFCF7 in light.
    static let cardSurface = adaptive(
        light: ui(0xFFFCF7),
        dark: ui(0x2A2622)
    )
    static let card = cardSurface

    /// Title and body. #2C2A26 in light. Not pure black.
    static let textCharcoal = adaptive(
        light: ui(0x2C2A26),
        dark: ui(0xF7F3EC)
    )
    static let ink = textCharcoal

    /// Charcoal at about 55% in light. System secondary in dark so it stays readable.
    static let secondaryText = adaptive(
        light: ui(0x2C2A26, alpha: 0.55),
        dark: .secondaryLabel
    )

    /// Success and progress only. #8FA88A. Not a primary color.
    static let sage = Color(red: 143.0 / 255.0, green: 168.0 / 255.0, blue: 138.0 / 255.0)

    static let shadow = adaptive(
        light: UIColor(white: 0, alpha: 0.06),
        dark: UIColor(white: 0, alpha: 0.28)
    )

    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 16

    private static func ui(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

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
    func mealCardSurface(fill: Color = Theme.cardSurface) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: Theme.shadow, radius: 12, y: 4)
    }

    func mealCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bgCream.ignoresSafeArea())
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
                .background(isSelected ? Theme.accent : Theme.cardSurface)
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textCharcoal)
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .shadow(color: isSelected ? Theme.accent.opacity(0.22) : Color.clear, radius: 6, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
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

/// Four-point sage track for cooked and grocery progress. Not a primary control.
struct ThinSageProgress: View {
    var value: Double
    var total: Double

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, value / total))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sage.opacity(0.28))
                Capsule()
                    .fill(Theme.sage)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 14)
            .background(
                isEnabled
                    ? Theme.accent.opacity(configuration.isPressed ? 0.82 : 1)
                    : Theme.textCharcoal.opacity(0.28)
            )
            .foregroundStyle(Theme.onAccent.opacity(isEnabled ? 1 : 0.85))
            .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
    }
}

/// Illustrated empty state. Symbols stay in SF Symbols; copy stays Turkish.
struct WarmEmptyState: View {
    var title: String
    var message: String
    var symbolName: String
    var accentSymbolName: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 10 : 16) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: isCompact ? 72 : 112, height: isCompact ? 72 : 112)
                Circle()
                    .fill(Theme.sage.opacity(0.32))
                    .frame(width: isCompact ? 40 : 68, height: isCompact ? 40 : 68)
                    .offset(x: isCompact ? 18 : 30, y: isCompact ? 12 : 20)
                Image(systemName: symbolName)
                    .font(.system(size: isCompact ? 26 : 36, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if let accentSymbolName {
                    Image(systemName: accentSymbolName)
                        .font(.system(size: isCompact ? 14 : 18, weight: .semibold))
                        .foregroundStyle(Theme.sage)
                        .offset(x: isCompact ? -22 : -34, y: isCompact ? -16 : -26)
                }
            }
            .accessibilityHidden(true)
            Text(title)
                .font(isCompact ? .headline : .title3.weight(.semibold))
                .foregroundStyle(Theme.textCharcoal)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(isCompact ? .subheadline : .body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(isCompact ? 8 : 28)
        .frame(
            maxWidth: .infinity,
            maxHeight: isCompact ? Optional<CGFloat>.none : Optional<CGFloat>.some(.infinity)
        )
        .background(isCompact ? Color.clear : Theme.bgCream)
        .accessibilityElement(children: .contain)
    }
}
