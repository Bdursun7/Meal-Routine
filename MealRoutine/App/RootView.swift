import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var prefs: [UserPrefs]
    @State private var household = HouseholdSession.shared
    @State private var auth = AuthSession.shared
    @State private var testMode = HouseholdTestMode.shared
    @State private var seedAttempt = 0
    @State private var isSeeding = true
    @State private var seedError: String?
    /// `-uitest` skips the intro so XCUITest can reach Bu Hafta without the hold.
    @State private var showsLaunchIntro = !UITestLaunch.isEnabled
    /// Stays up through the crossfade so a covered Bu Hafta is not hittable or exposed to VoiceOver.
    @State private var launchIntroCoversContent = !UITestLaunch.isEnabled

    private var didFinishOnboarding: Bool {
        prefs.contains { $0.hasCompletedOnboarding }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let notice = testMode.banner {
                    HouseholdTestBanner(notice: notice, onOpen: {
                        if let url = URL(string: notice.route) {
                            NotificationRouter.shared.apply(NotificationDeepLink.parse(url))
                        }
                        testMode.dismissBanner()
                    }, onDismiss: {
                        testMode.dismissBanner()
                    })
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                Group {
                    if isSeeding {
                        ProgressView("Tarifler yükleniyor…")
                            .tint(Theme.accent)
                    } else if let seedError {
                        ContentUnavailableView {
                            Label("Katalog açılamadı", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(seedError)
                        } actions: {
                            Button("Tekrar dene") {
                                seedAttempt += 1
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                    } else if didFinishOnboarding {
                        MainTabView()
                    } else {
                        OnboardingView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
            .accessibilityHidden(launchIntroCoversContent)
            .allowsHitTesting(!launchIntroCoversContent)

            if showsLaunchIntro {
                LaunchIntroView {
                    dismissLaunchIntro()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((showsLaunchIntro ? LaunchIntroPalette.background : Theme.canvas).ignoresSafeArea())
        .mealAppearance()
        .alert("Oturum sona erdi", isPresented: Binding(
            get: { auth.showsSessionExpired },
            set: { auth.showsSessionExpired = $0 }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Tekrar giriş yapman gerekiyor. Bu telefondaki kişisel verin durur.")
        }
        .task(id: seedAttempt) {
            await seedCatalog()
        }
        .onChange(of: household.pendingInviteCode) { _, code in
            guard let code, household.account != nil, !isSeeding else { return }
            Task { await household.acceptInvite(code: code, in: modelContext) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !isSeeding, seedError == nil else { return }
            drainCaptures()
            Task { await HouseholdSession.shared.start(in: modelContext) }
        }
        .onAppear {
            ProductEventSync.installIfNeeded()
            Analytics.trackOnce(.appOpened)
            SyncEngine.shared.start {
                Task { await HouseholdSession.shared.drainPending(in: modelContext) }
            }
            Task { await ProductEventSync.flushIfAllowed() }
        }
    }

    /// Crossfade only. `LaunchIntroTiming` already held the wordmark: no earlier
    /// than 3s, and no later than 4.5s when startup is still running.
    private func dismissLaunchIntro() {
        guard showsLaunchIntro else { return }
        let fade = reduceMotion ? 0.2 : LaunchIntroTiming.crossfadeSeconds
        withAnimation(reduceMotion ? .easeOut(duration: fade) : .easeInOut(duration: fade)) {
            showsLaunchIntro = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(fade * 1000) + 40))
            launchIntroCoversContent = false
        }
    }

    @MainActor
    private func drainCaptures() {
        do {
            let mapped = try RecipeCollectionService.drainCaptures(in: modelContext)
            CollectionRouter.shared.applyDrain(mapped)
        } catch {
            seedError = nil
        }
    }

    @MainActor
    private func seedCatalog() async {
        defer { LaunchStartup.shared.markCatalogFinished() }
        isSeeding = true
        seedError = nil
        LegacyPersonalPantryDateUpgrade.runIfNeeded(in: modelContext)
        do {
            if UITestLaunch.isEnabled {
                try UITestFixture.seed(in: modelContext)
            } else {
                try? GroceryListService.reconcileStoredShortfalls(in: modelContext)
                try await RecipeSeedService.seedIfNeeded(context: modelContext)
            }
            try CatalogIndexCache.warm(in: modelContext)
            isSeeding = false
            drainCaptures()
            await AuthSession.shared.restore()
            await HouseholdSession.shared.start(in: modelContext)
        } catch {
            seedError = error.localizedDescription
            isSeeding = false
        }
    }
}
