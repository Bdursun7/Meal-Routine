import XCTest
@testable import MealRoutine

@MainActor
final class NotificationTests: XCTestCase {
    func testDeepLinksRouteInvitePlanAndMeal() {
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "mealroutine://household/join?code=abcdef")!),
            .join(code: "ABCDEF")
        )
        XCTAssertEqual(NotificationDeepLink.parse(URL(string: "mealroutine://week")!), .week)
        XCTAssertEqual(
            NotificationDeepLink.parse(URL(string: "mealroutine://week/meal?id=test-meal")!),
            .meal(id: "test-meal")
        )
        XCTAssertEqual(
            NotificationDeepLink.parse(userInfo: ["route": "mealroutine://week"]),
            .week
        )
        XCTAssertEqual(
            NotificationDeepLink.parse(userInfo: ["kind": "meal_veto", "mealId": "meal-1"]),
            .meal(id: "meal-1")
        )
        XCTAssertEqual(NotificationDeepLink.parse(URL(string: "mealroutine://recipe?slug=corba")!), .unknown)

        let router = NotificationRouter()
        router.apply(.meal(id: "test-meal"))
        XCTAssertEqual(router.tab, .week)
        XCTAssertEqual(router.highlightedMealID, "test-meal")
        XCTAssertEqual(router.revision, 1)
        router.apply(.week)
        XCTAssertNil(router.highlightedMealID)
        XCTAssertEqual(router.tab, .week)
        router.apply(.join(code: "ABCDEF"))
        XCTAssertEqual(router.tab, .profile)
        XCTAssertTrue(router.showJoin)
        XCTAssertEqual(router.inviteCode, "ABCDEF")
        XCTAssertEqual(HouseholdSession.shared.pendingInviteCode, "ABCDEF")
        HouseholdSession.shared.pendingInviteCode = nil

        let banner = NotificationDeepLink.parse(URL(string: NotificationDeepLink.url(for: .veto))!)
        XCTAssertEqual(banner, .meal(id: "test-meal"))
    }

    func testPreferenceSyncRoundTrip() async throws {
        NotificationURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotificationURLProtocol.self]
        let client = NotificationHTTPClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://notifications.test")!,
            accessToken: "token"
        )
        let loaded = try await client.load()
        XCTAssertFalse(loaded.masterEnabled)
        XCTAssertFalse(loaded.mealVetoEnabled)
        var next = loaded
        next.masterEnabled = true
        next.mealVetoEnabled = true
        let saved = try await client.save(next)
        XCTAssertTrue(saved.masterEnabled)
        XCTAssertEqual(NotificationURLProtocol.putMaster, true)
        XCTAssertEqual(NotificationURLProtocol.putVeto, true)
        XCTAssertFalse(NotificationURLProtocol.bodies.contains { String(decoding: $0, as: UTF8.self).contains("Beyti") })
        NotificationURLProtocol.reset()
    }
}

private final class NotificationURLProtocol: URLProtocol {
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var putMaster: Bool?
    nonisolated(unsafe) static var putVeto: Bool?

    static func reset() {
        bodies = []
        putMaster = nil
        putVeto = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = NotificationURLProtocol.body(of: request)
        if !body.isEmpty {
            NotificationURLProtocol.bodies.append(body)
        }
        let path = request.url?.path ?? ""
        let data: Data
        if request.httpMethod == "PUT", path == "/v1/notifications/preferences" {
            if let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: body) {
                NotificationURLProtocol.putMaster = prefs.masterEnabled
                NotificationURLProtocol.putVeto = prefs.mealVetoEnabled
            }
            data = body
        } else {
            data = Data("""
            {"masterEnabled":false,"invitesEnabled":true,"weeklyPlanEnabled":true,"mealVetoEnabled":false,"mealReplacementEnabled":true,"planFinalizedEnabled":true}
            """.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://notifications.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
