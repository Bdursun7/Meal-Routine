import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    var account: AuthAccountDTO?
    var identities: [AuthIdentityDTO] = []
    var showsSessionExpired = false
    var statusMessage: String?
    var isWorking = false
    var exportedFile: URL?
    private var pendingGoogleToken: String?
    private var didInstallExpiry = false

    func restore() async {
        installExpiryHandler()
        guard let stored = AuthServices.sharedTokens.load() else { return }
        account = AuthAccountDTO(
            id: stored.accountId,
            displayName: stored.displayName,
            givenName: "",
            familyName: ""
        )
        adoptHousehold(id: stored.accountId, displayName: stored.displayName)
        do {
            let me = try await repository().me()
            account = me.account
            identities = me.identities
            adoptHousehold(id: me.account.id, displayName: me.account.displayName)
            statusMessage = nil
            await adoptRegional(me.settings)
        } catch AuthAPIError.sessionExpired {
            noteSessionExpired()
        } catch {
            statusMessage = AuthAPIError.transport.message
        }
    }

    func signInWithApple(identityToken: String, givenName: String?, familyName: String?) async {
        await run {
            let session = try await self.repository().signInWithApple(
                identityToken: identityToken,
                givenName: givenName,
                familyName: familyName
            )
            self.apply(session)
            if let pending = self.pendingGoogleToken {
                let linked = try await self.repository().link(
                    provider: "google",
                    identityToken: pending,
                    givenName: nil,
                    familyName: nil
                )
                self.pendingGoogleToken = nil
                self.apply(linked)
                self.statusMessage = "Google hesabı bağlandı."
            }
        }
    }

    func signInWithGoogle() async {
        do {
            let token = try await GoogleSignInCoordinator.signIn()
            await signInWithGoogleToken(token)
        } catch AuthAPIError.googleClientMissing {
            statusMessage = AuthAPIError.googleClientMissing.message
        } catch {
            statusMessage = "Google ile giriş tamamlanamadı."
        }
    }

    func signInWithGoogleToken(_ token: String) async {
        await run {
            do {
                let session = try await self.repository().signInWithGoogle(identityToken: token)
                self.pendingGoogleToken = nil
                self.apply(session)
            } catch AuthAPIError.linkRequired(let providers) {
                self.pendingGoogleToken = token
                self.statusMessage = AuthAPIError.linkRequired(existingProviders: providers).message
            }
        }
    }

    func signInLocalTest() async {
        let subject = DevSubjectStore.subject()
        await run {
            let session = try await self.repository().signInDev(subject: subject, displayName: "Yerel test")
            self.apply(session)
            if HouseholdTestMode.shared.isEnabled {
                self.statusMessage = "Sunucu oturumu açıldı. Test modu açıkken ev halkı sahte sunucuda kalır."
            } else {
                self.statusMessage = "Yerel test oturumu açıldı."
            }
        }
    }

    func linkApple(identityToken: String, givenName: String?, familyName: String?) async {
        await run {
            let session = try await self.repository().link(
                provider: "apple",
                identityToken: identityToken,
                givenName: givenName,
                familyName: familyName
            )
            self.apply(session)
            self.statusMessage = "Apple hesabı bağlandı."
        }
    }

    func linkGoogle() async {
        do {
            let token = try await GoogleSignInCoordinator.signIn()
            await run {
                let session = try await self.repository().link(
                    provider: "google",
                    identityToken: token,
                    givenName: nil,
                    familyName: nil
                )
                self.apply(session)
                self.statusMessage = "Google hesabı bağlandı."
            }
        } catch AuthAPIError.googleClientMissing {
            statusMessage = AuthAPIError.googleClientMissing.message
        } catch {
            statusMessage = "Google bağlanamadı."
        }
    }

    func unlink(_ provider: String) async {
        await run {
            let session = try await self.repository().unlink(provider: provider)
            self.apply(session)
            self.statusMessage = "\(AuthProviderLabel.title(provider)) bağlantısı kaldırıldı."
        }
    }

    func exportAccount() async {
        await run {
            let data = try await self.repository().exportData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mealroutine-verilerim.json")
            try data.write(to: url, options: .atomic)
            self.exportedFile = url
            self.statusMessage = AccountPrivacyCopy.exported
        }
    }

    func deleteAccount() async {
        await run {
            await NotificationSync.shared.unregisterCurrentToken()
            _ = try await self.repository().deleteAccount()
            AccountPrivacySession.clearTokens(AuthServices.sharedTokens)
            self.account = nil
            self.identities = []
            self.pendingGoogleToken = nil
            self.showsSessionExpired = false
            self.exportedFile = nil
            if !HouseholdTestMode.shared.isEnabled {
                HouseholdSession.shared.dropAccount(message: AccountPrivacyCopy.deleted)
            }
            self.statusMessage = AccountPrivacyCopy.deleted
        }
    }

    func signOut() async {
        await signOutTokensOnly()
        if !HouseholdTestMode.shared.isEnabled {
            HouseholdSession.shared.dropAccount(message: "Bu telefonda oturum kapatıldı.")
        }
        statusMessage = "Oturum kapatıldı."
    }

    func signOutTokensOnly() async {
        await NotificationSync.shared.unregisterCurrentToken()
        let refresh = AuthServices.sharedTokens.load()?.refreshToken
        AuthServices.sharedTokens.clear()
        account = nil
        identities = []
        pendingGoogleToken = nil
        showsSessionExpired = false
        guard let refresh else { return }
        await repository().logout(refreshToken: refresh)
    }

    func completeApple(_ result: Result<ASAuthorization, Error>, linking: Bool) async {
        switch result {
        case .failure:
            statusMessage = "Apple ile giriş tamamlanamadı."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  !token.isEmpty else {
                statusMessage = "Apple kimlik jetonu gelmedi."
                return
            }
            if linking {
                await linkApple(
                    identityToken: token,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
            } else {
                await signInWithApple(
                    identityToken: token,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
            }
        }
    }

    func noteSessionExpired() {
        account = nil
        identities = []
        pendingGoogleToken = nil
        showsSessionExpired = true
        statusMessage = AuthAPIError.sessionExpired.message
        if !HouseholdTestMode.shared.isEnabled {
            HouseholdSession.shared.dropAccount(message: AuthAPIError.sessionExpired.message)
        }
    }

    private func apply(_ session: AuthSessionDTO) {
        let wasSignedOut = account == nil
        let stored = APIClient.tokenSet(from: session, now: .now)
        AuthServices.sharedTokens.save(stored)
        account = session.account
        identities = session.identities
        showsSessionExpired = false
        adoptHousehold(id: session.account.id, displayName: session.account.displayName)
        if wasSignedOut {
            Analytics.track(.signIn)
        }
        if let settings = session.settings {
            Task { await self.adoptRegional(settings) }
        }
    }

    /// Account settings replace the device copy; onboarding values still pending are uploaded once.
    private func adoptRegional(_ server: RegionalSettings?) async {
        guard let server else { return }
        let resolved = RegionalSettingsStore.reconcile(server: server, stored: RegionalSettingsStore.load())
        RegionalSettingsStore.save(StoredRegionalSettings(settings: resolved.settings, pendingUpload: resolved.upload != nil))
        RegionalContext.shared.apply(user: resolved.settings)
        guard let patch = resolved.upload,
              let saved = try? await repository().updateAccountSettings(patch) else { return }
        RegionalSettingsStore.save(StoredRegionalSettings(settings: saved, pendingUpload: false))
        RegionalContext.shared.apply(user: saved)
    }

    private func adoptHousehold(id: String, displayName: String) {
        guard !HouseholdTestMode.shared.isEnabled else { return }
        HouseholdSession.shared.adoptAccount(id: id, displayName: displayName)
    }

    private func run(_ work: () async throws -> Void) async {
        installExpiryHandler()
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as AuthAPIError {
            if case .linkRequired = error {
                return
            }
            if case .sessionExpired = error {
                noteSessionExpired()
                return
            }
            statusMessage = error.message
        } catch {
            statusMessage = AuthAPIError.transport.message
        }
    }

    private func repository() -> AccountRepository {
        let base = MealRoutineConfig.apiBaseURL ?? URL(string: "http://127.0.0.1:8080")!
        return AccountRepository(
            client: APIClient(
                baseURL: base,
                tokens: AuthServices.sharedTokens,
                refreshGate: AuthServices.refreshGate,
                expiry: AuthServices.expiry
            )
        )
    }

    private func installExpiryHandler() {
        guard !didInstallExpiry else { return }
        didInstallExpiry = true
        AuthServices.expiry.setHandler {
            Task { @MainActor in
                AuthSession.shared.noteSessionExpired()
            }
        }
    }
}
