import AuthenticationServices
import SwiftData
import SwiftUI

struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var auth = AuthSession.shared
    @State private var migration = LocalMigrationCenter.shared
    @State private var providerPendingUnlink: String?

    var body: some View {
        Form {
            if auth.isWorking {
                Section {
                    HStack {
                        ProgressView()
                        Text("Hesap eşitleniyor…")
                    }
                    .accessibilityLabel("Hesap eşitleniyor")
                }
            }
            if let message = auth.statusMessage, !message.isEmpty {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if auth.account == nil {
                Section {
                    Text("Giriş yapınca kişisel tariflerin ve yemek hafızan bu hesaba bağlanabilir. Ev halkı ayrı kalır.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    AccountSignInButtons()
                } header: {
                    Text("Giriş")
                }
            } else {
                Section {
                    Text(displayName)
                        .font(.headline)
                    if auth.identities.isEmpty {
                        Text("Bağlı giriş yok.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(auth.identities) { identity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AuthProviderLabel.title(identity.provider))
                            if identity.isPrivateRelay {
                                Text("Gizli e-posta")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            } else if let email = identity.email, !email.isEmpty {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        if auth.identities.count > 1 {
                            Button("\(AuthProviderLabel.title(identity.provider)) bağlantısını kaldır", role: .destructive) {
                                providerPendingUnlink = identity.provider
                            }
                        }
                    }
                } header: {
                    Text("Bağlı girişler")
                }
                linkSection
                Section {
                    Button("Oturumu kapat", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .accessibilityIdentifier("account.signOut")
                }
                migrationSection
            }
            if auth.account == nil, HouseholdTestMode.shared.isEnabled {
                migrationSection
            }
        }
        .navigationTitle("Hesap")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Bu girişi kaldırmak istiyor musun?",
            isPresented: Binding(
                get: { providerPendingUnlink != nil },
                set: { if !$0 { providerPendingUnlink = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Kaldır", role: .destructive) {
                let provider = providerPendingUnlink
                providerPendingUnlink = nil
                guard let provider else { return }
                Task { await auth.unlink(provider) }
            }
            Button("Vazgeç", role: .cancel) {
                providerPendingUnlink = nil
            }
        }
        .task {
            await auth.restore()
            await migration.runIfNeeded(in: modelContext)
        }
    }

    @ViewBuilder
    private var migrationSection: some View {
        Section {
            Text(migration.record.headline)
                .accessibilityIdentifier("migration.progress")
            Text("Tarif: \(migration.record.recipes)")
            Text("Yemek hafızası: \(migration.record.memories)")
            Text("Geçmiş: \(migration.record.history)")
            if migration.record.phase == .failed {
                Button("Yeniden dene") {
                    Task { await migration.runIfNeeded(in: modelContext) }
                }
                .accessibilityIdentifier("migration.retry")
            }
            if HouseholdTestMode.shared.isEnabled {
                Button("Test aktarımını dene") {
                    Task { await migration.runFake(in: modelContext) }
                }
                .accessibilityIdentifier("migration.testRun")
            }
        } header: {
            Text("Aktarım")
        }
    }

    private var displayName: String {
        let name = auth.account?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "İsimsiz hesap" : name
    }

    @ViewBuilder
    private var linkSection: some View {
        let linked = Set(auth.identities.map(\.provider))
        if !linked.contains("apple") || !linked.contains("google") {
            Section {
                if !linked.contains("apple") {
                    if HouseholdTestLaunch.allowsAppleServices {
                        Text("Apple hesabını bağla")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            Task { await auth.completeApple(result, linking: true) }
                        }
                        .frame(height: 44)
                        .accessibilityLabel("Apple hesabını bağla")
                    } else {
                        Text("Bu derleme Apple ile girişi imzalamaz. Bağlamak için Apple yetkisi olan derlemeyi kullan.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if !linked.contains("google") {
                    if MealRoutineConfig.googleClientID.isEmpty {
                        Text(MealRoutineConfig.googleClientMissingMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Button("Google bağla") {
                            Task { await auth.linkGoogle() }
                        }
                        .accessibilityIdentifier("account.linkGoogle")
                    }
                }
            } header: {
                Text("Başka giriş bağla")
            }
        }
    }
}

struct AccountSignInButtons: View {
    @State private var auth = AuthSession.shared

    var body: some View {
        if HouseholdTestLaunch.allowsAppleServices {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await auth.completeApple(result, linking: false) }
            }
            .frame(height: 44)
            .accessibilityLabel("Apple ile giriş yap")
        } else {
            Text("Bu derleme Apple ile girişi imzalamaz. Ücretsiz deneme için Yerel test girişi sunucuya gider.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }

        if MealRoutineConfig.googleClientID.isEmpty {
            Text(MealRoutineConfig.googleClientMissingMessage)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("auth.googleMissing")
        } else {
            Button("Google ile giriş") {
                Task { await auth.signInWithGoogle() }
            }
            .accessibilityIdentifier("auth.google")
        }

        #if HOUSEHOLD_LOCAL
        Button("Yerel test girişi") {
            Task { await auth.signInLocalTest() }
        }
        .accessibilityIdentifier("auth.localTestSignIn")
        #endif
    }
}
