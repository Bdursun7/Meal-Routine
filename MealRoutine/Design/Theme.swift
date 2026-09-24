import SwiftUI
import UIKit

/// Cream ground, muted-green symbols, warm-orange emphasis, dark-green text.
/// Measured from the palette: #F2E8D9, #45604C, #E89758, #29342F.
/// Dark mode uses the system background. The symbol green is lifted so it stays readable.
enum Theme {
    /// Vurgu. #E89758. Button fills, selected chips, and the MealRoutine word.
    /// Too light for small type on cream; those labels use `sage` or `textCharcoal`.
    static let accent = Color(uiColor: ui(0xE89758))
    static let primary = accent

    /// Kontrast on the orange fill. #29342F in both modes.
    static let onAccent = Color(uiColor: ui(0x29342F))

    /// Ana zemin. #F2E8D9 in light. System background in dark.
    static let canvasUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBackground : ui(0xF2E8D9)
    }
    static let bgCream = Color(uiColor: canvasUIColor)
    static let canvas = bgCream
    static let cream = bgCream

    /// Lifted cream in light. Elevated system surface in dark.
    static let cardUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : ui(0xFFF8EF)
    }
    static let cardSurface = Color(uiColor: cardUIColor)
    static let card = cardSurface

    /// Kontrast. #29342F in light. System label in dark.
    static let textCharcoal = adaptive(
        light: ui(0x29342F),
        dark: .label
    )
    static let ink = textCharcoal

    /// Dark green at 72% on cream, which stays above 4.5:1. System secondary in dark.
    static let secondaryText = adaptive(
        light: ui(0x29342F, alpha: 0.72),
        dark: .secondaryLabel
    )

    /// Ana sembol. #45604C in light. #7D9082 in dark, the same hue lifted for contrast.
    static let sage = adaptive(
        light: ui(0x45604C),
        dark: ui(0x7D9082)
    )

    /// Soft lift for cards. Light is black at 10%. Dark is heavier so the edge still reads.
    static let cardShadow = adaptive(
        light: UIColor(white: 0, alpha: 0.10),
        dark: UIColor(white: 0, alpha: 0.42)
    )
    /// Tonight and other magazine cards. Light is black at 14%.
    static let elevatedShadow = adaptive(
        light: UIColor(white: 0, alpha: 0.14),
        dark: UIColor(white: 0, alpha: 0.50)
    )
    static let shadow = cardShadow

    /// Black at the top, clear by the middle. About 35% at the dark end.
    static let scrimTop = LinearGradient(
        colors: [Color.black.opacity(0.35), Color.clear],
        startPoint: .top,
        endPoint: .center
    )
    /// Clear through the photo, darkening to about 35% where a caption sits.
    static let scrimBottom = LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.20), Color.black.opacity(0.55)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 16
    static let heroCorner: CGFloat = 24
    static let sheetCorner: CGFloat = 28
    static let screenPadding: CGFloat = 20
    static let cardGap: CGFloat = 16
    static let sectionGap: CGFloat = 28

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
            .shadow(color: Theme.cardShadow, radius: 8, y: 3)
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
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Theme.textCharcoal.opacity(0.16),
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

/// Four-point muted-green track for cooked and grocery progress. Not a primary control.
struct ThinSageProgress: View {
    var value: Double
    var total: Double
    var height: CGFloat = 4

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
        .frame(height: height)
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

/// Rounded-square check used on recipe ingredients and market rows.
struct MealCheckBox: View {
    var isChecked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isChecked ? Theme.sage : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isChecked ? Theme.sage : Theme.secondaryText.opacity(0.85), lineWidth: 1.5)
            }
            .overlay {
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
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
                    .fill(Theme.cardSurface)
                    .frame(width: isCompact ? 72 : 132, height: isCompact ? 72 : 132)
                Circle()
                    .fill(Theme.sage.opacity(0.35))
                    .frame(width: isCompact ? 40 : 76, height: isCompact ? 40 : 76)
                    .offset(x: isCompact ? 18 : 30, y: isCompact ? 12 : 20)
                Image(systemName: symbolName)
                    .font(.system(size: isCompact ? 26 : 36, weight: .semibold))
                    .foregroundStyle(Theme.sage)
                if let accentSymbolName {
                    Image(systemName: accentSymbolName)
                        .font(.system(size: isCompact ? 14 : 18, weight: .semibold))
                        .foregroundStyle(Theme.textCharcoal)
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
                    .buttonStyle(PrimaryButtonStyle())
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
