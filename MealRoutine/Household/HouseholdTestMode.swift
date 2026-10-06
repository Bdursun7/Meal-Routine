import Foundation
import Observation

/// Launch argument for UI tests and a fresh simulator run: `-HouseholdTestMode`.
/// `-HouseholdTestReset` wipes the test household once at startup so a UI test
/// does not reuse a household left on the simulator.
enum HouseholdTestLaunch {
    static let argument = "-HouseholdTestMode"
    static let resetArgument = "-HouseholdTestReset"
    static let storageKey = "mealroutine.householdTestMode"

    static var isRequestedByLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var isResetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(resetArgument)
    }

    /// Apple sign-in, CloudKit, and push stay off for this process.
    static var allowsAppleServices: Bool {
        if isRequestedByLaunch || UserDefaults.standard.bool(forKey: storageKey) {
            return false
        }
        #if HOUSEHOLD_LOCAL
        return false
        #else
        return true
        #endif
    }
}

enum HouseholdTestAudience: String, Codable, Sendable {
    case local
    case partner
}

struct HouseholdTestNotice: Identifiable, Equatable, Sendable {
    var id: UUID
    var audience: HouseholdTestAudience
    var title: String
    var body: String
    var route: String = ""
    var createdAt: Date

    var bannerText: String {
        switch audience {
        case .local:
            body
        case .partner:
            "Test Partner görür: \(body)"
        }
    }
}

/// Stable stand-in for the second member. Taste signals are fake, not a copy of anyone's memory.
enum HouseholdTestPartner {
    static let localUserID = "test-user-local"
    static let localDisplayName = "Test Kullanıcı"
    static let userID = "test-partner"
    static let displayName = "Test Partner"

    static func user(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> HouseholdUser {
        HouseholdUser(id: userID, displayName: displayName, createdAt: now)
    }

    /// Loved, okay, and a personal Never Again so shared scoring has something to rank.
    static func taste(now: Date = .now) -> MemberTasteProjection {
        let loved = MealMemorySnapshot(
            recipeID: "menemen",
            timesCooked: 4,
            lovedCount: 3,
            latestRating: .loved,
            isFavorite: true
        )
        let okay = MealMemorySnapshot(
            recipeID: "mercimek-corbasi",
            timesCooked: 2,
            okayCount: 2,
            latestRating: .okay
        )
        let never = MealMemorySnapshot(
            recipeID: "iskender-kebab",
            timesCooked: 1,
            latestRating: .never,
            neverAgain: true
        )
        let favorite = MealMemorySnapshot(
            recipeID: "lahmacun",
            timesCooked: 3,
            lovedCount: 2,
            latestRating: .loved,
            isFavorite: true
        )
        return MemberTasteProjectionBuilder.make(
            userId: userID,
            displayName: displayName,
            memories: [
                loved.recipeID: loved,
                okay.recipeID: okay,
                never.recipeID: never,
                favorite.recipeID: favorite,
            ],
            dislikedIngredientIds: ["mushroom"],
            now: now
        )
    }
}

/// Test-mode switch, fake sign-in flag, and the in-app stand-in for push.
@MainActor
@Observable
final class HouseholdTestMode {
    static let shared = HouseholdTestMode()

    private(set) var isEnabled: Bool
    /// Keeps shared edits on this phone and skips the fake server.
    var simulateOffline = false
    /// The next meal edit is treated as losing to the other device.
    var simulatePartnerEdit = false
    var notices: [HouseholdTestNotice] = []
    var banner: HouseholdTestNotice?
    private var deliveredNoticeIDs: Set<UUID> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        let stored = defaults.bool(forKey: HouseholdTestLaunch.storageKey)
        let requested = launchArguments.contains(HouseholdTestLaunch.argument)
        isEnabled = requested || stored
        if requested {
            defaults.set(true, forKey: HouseholdTestLaunch.storageKey)
            isEnabled = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: HouseholdTestLaunch.storageKey)
        if !enabled { clearSyncSimulation() }
    }

    func clearSyncSimulation() {
        simulateOffline = false
        simulatePartnerEdit = false
    }

    func record(_ pushes: [HouseholdPush], audience: HouseholdTestAudience) {
        let fresh = pushes.filter { !deliveredNoticeIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let created = fresh.map { push in
            deliveredNoticeIDs.insert(push.id)
            return HouseholdTestNotice(
                id: push.id,
                audience: audience,
                title: push.title,
                body: push.body,
                route: NotificationDeepLink.url(for: push.kind),
                createdAt: .now
            )
        }
        notices.insert(contentsOf: created.reversed(), at: 0)
        banner = created.last
    }

    func dismissBanner() {
        banner = nil
    }

    func clearNotices() {
        notices = []
        banner = nil
        deliveredNoticeIDs = []
    }
}
