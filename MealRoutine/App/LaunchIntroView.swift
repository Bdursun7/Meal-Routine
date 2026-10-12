import SwiftUI

/// How long the branded intro stays up.
///
/// Startup work keeps running underneath. The intro never waits past `maximum`,
/// and it does not leave before `minimum` even when that work finished early.
enum LaunchIntroTiming {
    static let minimum: Duration = .milliseconds(1500)
    static let maximum: Duration = .milliseconds(3000)
    static let crossfadeSeconds: Double = 0.45

    static func shouldDismiss(elapsed: Duration, startupReady: Bool) -> Bool {
        if elapsed >= maximum { return true }
        return elapsed >= minimum && startupReady
    }
}

enum LaunchIntroCopy {
    /// Locked launch subtitle.
    static let subtitle = "Bu haftan hazırlanıyor…"
    static let accessibilityLabel = "MealRoutine. Bu haftan hazırlanıyor."
}

/// First frame of the intro. Matches the `LaunchBackground` color asset used by `UILaunchScreen`.
enum LaunchIntroPalette {
    static let background = Color(red: 28.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0)
    static let cream = Color(red: 247.0 / 255.0, green: 243.0 / 255.0, blue: 236.0 / 255.0)
    static let ceramic = Color(red: 0.965, green: 0.925, blue: 0.875)
    static let well = Color(red: 0.890, green: 0.835, blue: 0.760)
}

/// Catalog seed, session restore, and household start share one flag.
/// Remote config / server-address resolve shares the other.
/// The intro reads both and still moves on at three seconds.
@MainActor
final class LaunchStartup {
    static let shared = LaunchStartup()

    private(set) var catalogFinished = false
    private(set) var remoteConfigFinished = false

    var isReady: Bool { catalogFinished && remoteConfigFinished }

    func markCatalogFinished() {
        catalogFinished = true
    }

    func markRemoteConfigFinished() {
        remoteConfigFinished = true
    }
}

/// Plate, orbiting ingredients, then the MealRoutine wordmark.
/// Reduce Motion fades the wordmark in and skips the orbit.
struct LaunchIntroView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plateIn = false
    @State private var orbit = 0.0
    @State private var dropped = false
    @State private var morphed = false
    @State private var subtitleIn = false

    var body: some View {
        ZStack {
            LaunchIntroPalette.background
                .ignoresSafeArea()

            if reduceMotion {
                stillMark
            } else {
                stagedMark
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LaunchIntroCopy.accessibilityLabel)
        .accessibilityAddTraits(.isModal)
        .task { await playAndGate() }
    }

    private var stillMark: some View {
        wordmark
            .opacity(morphed ? 1 : 0)
    }

    private var stagedMark: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.accent.opacity(0.28), Color.clear],
                center: .center,
                startRadius: 12,
                endRadius: 280
            )
            .opacity(plateIn ? 1 : 0)
            .animation(.easeIn(duration: 0.45), value: plateIn)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            plate
                .scaleEffect(plateIn ? (morphed ? 0.48 : 1) : 0.12)
                .offset(y: morphed ? -62 : 0)
                .opacity(plateIn ? 1 : 0)
                .animation(.spring(response: 0.48, dampingFraction: 0.68), value: plateIn)
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: morphed)

            ForEach(LaunchIngredient.orbit) { item in
                let angle = item.baseAngle + orbit * 210
                Image(systemName: item.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .rotationEffect(.degrees(-angle))
                    .offset(y: dropped ? 0 : -120)
                    .rotationEffect(.degrees(angle))
                    .scaleEffect(dropped ? 0.12 : (plateIn ? 1 : 0.3))
                    .opacity(dropped ? 0 : (plateIn ? 1 : 0))
                    .animation(.easeInOut(duration: 0.62), value: orbit)
                    .animation(.spring(response: 0.46, dampingFraction: 0.62), value: plateIn)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.55).delay(Double(item.id) * 0.05),
                        value: dropped
                    )
                    .accessibilityHidden(true)
            }

            wordmark
                .scaleEffect(morphed ? 1 : 0.42)
                .opacity(morphed ? 1 : 0)
                .offset(y: morphed ? 42 : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: morphed)
        }
    }

    private var plate: some View {
        ZStack {
            Ellipse()
                .fill(LaunchIntroPalette.ceramic)
            Ellipse()
                .fill(LaunchIntroPalette.well)
                .padding(28)
                .offset(y: 6)
            Ellipse()
                .strokeBorder(Theme.accent, lineWidth: 8)
            Ellipse()
                .strokeBorder(Theme.accent.opacity(0.38), lineWidth: 2)
                .padding(22)
        }
        .frame(width: 176, height: 176)
        .shadow(color: Color.black.opacity(0.38), radius: 18, y: 12)
        .accessibilityHidden(true)
    }

    private var wordmark: some View {
        VStack(spacing: 10) {
            Text("MealRoutine")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(LaunchIntroPalette.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Capsule()
                .fill(Theme.accent)
                .frame(width: subtitleIn || reduceMotion ? 72 : 16, height: 4)
                .opacity(morphed ? 1 : 0)
            Text(LaunchIntroCopy.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LaunchIntroPalette.cream.opacity(0.74))
                .multilineTextAlignment(.center)
                .opacity(subtitleIn ? 1 : 0)
                .offset(y: subtitleIn ? 0 : 8)
        }
        .padding(.horizontal, 24)
        .animation(.easeOut(duration: 0.32), value: subtitleIn)
    }

    private func playAndGate() async {
        let clock = ContinuousClock()
        let start = clock.now
        let visual = Task { @MainActor in
            await playVisual()
        }
        await holdUntilDismissible(since: start, clock: clock)
        visual.cancel()
        guard !Task.isCancelled else { return }
        onFinished()
    }

    private func playVisual() async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.35)) {
                morphed = true
                subtitleIn = true
            }
            return
        }

        plateIn = true
        guard await pause(100) else { return }
        orbit = 1
        guard await pause(640) else { return }
        dropped = true
        guard await pause(260) else { return }
        morphed = true
        guard await pause(70) else { return }
        subtitleIn = true
    }

    private func holdUntilDismissible(since start: ContinuousClock.Instant, clock: ContinuousClock) async {
        while !Task.isCancelled {
            let elapsed = start.duration(to: clock.now)
            if LaunchIntroTiming.shouldDismiss(elapsed: elapsed, startupReady: LaunchStartup.shared.isReady) {
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
        }
    }

    private func pause(_ milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct LaunchIngredient: Identifiable {
    let id: Int
    let symbol: String
    let baseAngle: Double
    let tint: Color

    static let orbit: [LaunchIngredient] = [
        LaunchIngredient(id: 0, symbol: "leaf.fill", baseAngle: -90, tint: Theme.sage),
        LaunchIngredient(id: 1, symbol: "carrot.fill", baseAngle: -30, tint: Theme.accent),
        LaunchIngredient(id: 2, symbol: "fish.fill", baseAngle: 30, tint: Color(red: 0.55, green: 0.76, blue: 0.84)),
        LaunchIngredient(id: 3, symbol: "fork.knife", baseAngle: 90, tint: LaunchIntroPalette.cream),
        LaunchIngredient(id: 4, symbol: "flame.fill", baseAngle: 150, tint: Color(red: 0.93, green: 0.55, blue: 0.27)),
        LaunchIngredient(id: 5, symbol: "cup.and.saucer.fill", baseAngle: 210, tint: LaunchIntroPalette.cream),
    ]
}
