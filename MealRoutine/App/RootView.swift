import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefs: [UserPrefs]
    @State private var seedAttempt = 0
    @State private var isSeeding = true
    @State private var seedError: String?

    private var didFinishOnboarding: Bool {
        prefs.contains { $0.hasCompletedOnboarding }
    }

    var body: some View {
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
        .task(id: seedAttempt) {
            await seedCatalog()
        }
    }

    @MainActor
    private func seedCatalog() async {
        isSeeding = true
        seedError = nil
        do {
            try RecipeSeedService.seedIfNeeded(context: modelContext)
            isSeeding = false
        } catch {
            seedError = error.localizedDescription
            isSeeding = false
        }
    }
}
