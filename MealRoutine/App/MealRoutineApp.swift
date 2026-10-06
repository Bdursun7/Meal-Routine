import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

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
                    let route = NotificationDeepLink.parse(url)
                    if route != .unknown {
                        NotificationRouter.shared.apply(route)
                        return
                    }
                    CollectionRouter.shared.handleOpenURL(url)
                }
        }
        .modelContainer(container)
    }
}

final class MealRoutineAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GoogleSignInCoordinator.configureIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await NotificationSync.shared.registerToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        _ = error
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = NotificationDeepLink.parse(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            NotificationRouter.shared.apply(route)
        }
    }
}
