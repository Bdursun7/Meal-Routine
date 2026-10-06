import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit

@main
struct MealRoutineApp: App {
    @UIApplicationDelegateAdaptor(MealRoutineAppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainerFactory.make()
        } catch {
            fatalError("MealRoutine SwiftData store could not be created: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    if let code = HouseholdInviteLink.code(from: url) {
                        HouseholdSession.shared.queueInvite(code)
                        return
                    }
                    CollectionRouter.shared.handleOpenURL(url)
                }
        }
        .modelContainer(container)
    }
}

final class MealRoutineAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GoogleSignInCoordinator.configureIfNeeded()
        if HouseholdTestLaunch.allowsAppleServices {
            application.registerForRemoteNotifications()
        }
        return true
    }
}
