import Foundation

enum NotificationRoute: Equatable, Sendable {
    case join(code: String)
    case week
    case meal(id: String)
    case unknown
}

enum NotificationDeepLink {
    static func parse(_ url: URL) -> NotificationRoute {
        guard url.scheme?.lowercased() == "mealroutine" else { return .unknown }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "household" && (path == "/join" || path == "/" || path.isEmpty) {
            let code = HouseholdInviteCode.normalize(query(url, named: "code") ?? "")
            return .join(code: code)
        }
        if host == "week", path == "/meal" {
            let mealID = query(url, named: "id") ?? ""
            if mealID.isEmpty { return .week }
            return .meal(id: mealID)
        }
        if host == "week" {
            return .week
        }
        return .unknown
    }

    static func parse(userInfo: [AnyHashable: Any]) -> NotificationRoute {
        if let route = userInfo["route"] as? String, let url = URL(string: route) {
            let parsed = parse(url)
            if parsed != .unknown { return parsed }
        }
        guard let kind = userInfo["kind"] as? String else { return .unknown }
        switch kind {
        case "invite":
            return .join(code: HouseholdInviteCode.normalize(userInfo["code"] as? String ?? ""))
        case "meal_veto", "meal_replacement":
            if let mealID = userInfo["mealId"] as? String, !mealID.isEmpty {
                return .meal(id: mealID)
            }
            return .week
        case "weekly_plan", "plan_finalized":
            return .week
        default:
            return .unknown
        }
    }

    static func url(for kind: HouseholdNotificationKind) -> String {
        switch kind {
        case .planReview, .planFinalized:
            "mealroutine://week"
        case .veto, .replacement:
            "mealroutine://week/meal?id=test-meal"
        }
    }

    private static func query(_ url: URL, named name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    private(set) var tab: AppTab = .week
    private(set) var revision = 0
    private(set) var highlightedMealID: String?
    private(set) var showJoin = false
    private(set) var inviteCode = ""

    func apply(_ route: NotificationRoute) {
        switch route {
        case .join(let code):
            tab = .profile
            showJoin = true
            inviteCode = code
            highlightedMealID = nil
            if !code.isEmpty {
                HouseholdSession.shared.queueInvite(code)
            }
        case .week:
            tab = .week
            showJoin = false
            highlightedMealID = nil
        case .meal(let id):
            tab = .week
            showJoin = false
            highlightedMealID = id
        case .unknown:
            return
        }
        revision += 1
    }

    func clearJoin() {
        showJoin = false
    }
}
