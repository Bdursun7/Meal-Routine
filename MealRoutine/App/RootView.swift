import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var prefs: [UserPrefs]
    @State private var household = HouseholdSession.shared
    @State private var auth = AuthSession.shared
    @State private var testMode = HouseholdTestMode.shared
    @State private var seedAttempt = 0
    @State private var isSeeding = true
    @State private var seedError: String?

    private var didFinishOnboarding: Bool {
        prefs.contains { $0.hasCompletedOnboarding }
    }

    var body: some View {
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
            Analytics.trackOnce(.appOpened)
            SyncEngine.shared.start {
                Task { await HouseholdSession.shared.drainPending(in: modelContext) }
            }
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
        isSeeding = true
        seedError = nil
        do {
            try await RecipeSeedService.seedIfNeeded(context: modelContext)
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
