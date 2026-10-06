import GoogleSignIn
import UIKit

enum GoogleSignInCoordinator {
    @MainActor
    static func configureIfNeeded() {
        let clientID = MealRoutineConfig.googleClientID
        guard !clientID.isEmpty else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    @MainActor
    static func signIn() async throws -> String {
        let clientID = MealRoutineConfig.googleClientID
        guard !clientID.isEmpty else { throw AuthAPIError.googleClientMissing }
        configureIfNeeded()
        guard let controller = topViewController() else {
            throw AuthAPIError.server("Google penceresi açılamadı.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: controller) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token = result?.user.idToken?.tokenString, !token.isEmpty else {
                    continuation.resume(throwing: AuthAPIError.server("Google kimlik jetonu gelmedi."))
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
