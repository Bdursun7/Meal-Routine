import Foundation
import MetricKit

/// One in-flight refresh so parallel API calls do not rotate the token twice.
actor RefreshGate {
    private var task: Task<AuthTokenSet, Error>?

    func run(_ work: @escaping @Sendable () async throws -> AuthTokenSet) async throws -> AuthTokenSet {
        if let task {
            return try await task.value
        }
        let task = Task { try await work() }
        self.task = task
        defer { self.task = nil }
        return try await task.value
    }
}

struct APIClient: Sendable {
    var baseURL: URL
    var session: URLSession
    var tokens: any TokenStoring
    var now: @Sendable () -> Date
    var refreshGate: RefreshGate
    var expiry: SessionExpiryCenter

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokens: any TokenStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshGate: RefreshGate = AuthServices.refreshGate,
        expiry: SessionExpiryCenter = AuthServices.expiry
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
        self.now = now
        self.refreshGate = refreshGate
        self.expiry = expiry
    }

    func request(
        method: String,
        path: String,
        body: Data?,
        authenticated: Bool,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        let access = try await accessToken(authenticated: authenticated)
        let first = try await perform(method: method, path: path, body: body, accessToken: access, headers: headers)
        guard authenticated, first.response.statusCode == 401 else {
            return (first.data, first.response)
        }
        guard let current = tokens.load() else {
            expiry.emit()
            throw AuthAPIError.sessionExpired
        }
        let refreshed = try await refresh(current, force: true)
        let second = try await perform(method: method, path: path, body: body, accessToken: refreshed.accessToken, headers: headers)
        if second.response.statusCode == 401 {
            tokens.clear()
            expiry.emit()
            throw AuthAPIError.sessionExpired
        }
        return (second.data, second.response)
    }

    func validateAuth(_ response: HTTPURLResponse, data: Data, authenticated: Bool) throws {
        if (200..<300).contains(response.statusCode) { return }
        let body = try? JSONDecoder().decode(APIErrorDTO.self, from: data)
        switch response.statusCode {
        case 401:
            if authenticated {
                throw AuthAPIError.sessionExpired
            }
            throw AuthAPIError.server("Giriş doğrulanamadı.")
        case 409 where body?.error == "link_required":
            throw AuthAPIError.linkRequired(existingProviders: body?.existingProviders ?? [])
        case 429:
            throw AuthAPIError.rateLimited
        case 503 where body?.error == "google_not_configured":
            throw AuthAPIError.googleClientMissing
        default:
            throw AuthAPIError.server(Self.message(for: body?.error))
        }
    }

    static func tokenSet(from dto: AuthSessionDTO, now: Date) -> AuthTokenSet {
        AuthTokenSet(
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken,
            accessExpiresAt: now.addingTimeInterval(TimeInterval(max(dto.expiresIn, 0))),
            accountId: dto.account.id,
            displayName: dto.account.displayName
        )
    }

    private func accessToken(authenticated: Bool) async throws -> String? {
        guard authenticated else { return nil }
        guard let current = tokens.load() else { throw AuthAPIError.sessionExpired }
        if TokenRefreshPolicy.needsRefresh(accessExpiresAt: current.accessExpiresAt, now: now()) {
            return try await refresh(current, force: false).accessToken
        }
        return current.accessToken
    }

    private func refresh(_ current: AuthTokenSet, force: Bool) async throws -> AuthTokenSet {
        let tokens = self.tokens
        let session = self.session
        let baseURL = self.baseURL
        let now = self.now
        let expiry = self.expiry
        return try await refreshGate.run {
            if !force,
               let latest = tokens.load(),
               latest.accessToken != current.accessToken,
               !TokenRefreshPolicy.needsRefresh(accessExpiresAt: latest.accessExpiresAt, now: now()) {
                return latest
            }
            let body = try JSONEncoder().encode(RefreshPayload(refreshToken: current.refreshToken))
            let result = try await APIClient.perform(
                session: session,
                baseURL: baseURL,
                method: "POST",
                path: "/v1/auth/refresh",
                body: body,
                accessToken: nil
            )
            if result.response.statusCode == 401 {
                tokens.clear()
                expiry.emit()
                throw AuthAPIError.sessionExpired
            }
            let client = APIClient(baseURL: baseURL, session: session, tokens: tokens, now: now, expiry: expiry)
            try client.validateAuth(result.response, data: result.data, authenticated: false)
            let dto = try JSONDecoder().decode(AuthSessionDTO.self, from: result.data)
            let stored = APIClient.tokenSet(from: dto, now: now())
            tokens.save(stored)
            return stored
        }
    }

    private func perform(
        method: String,
        path: String,
        body: Data?,
        accessToken: String?,
        headers: [String: String] = [:]
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        try await APIClient.perform(
            session: session,
            baseURL: baseURL,
            method: method,
            path: path,
            body: body,
            accessToken: accessToken,
            headers: headers
        )
    }

    private static func perform(
        session: URLSession,
        baseURL: URL,
        method: String,
        path: String,
        body: Data?,
        accessToken: String?,
        headers: [String: String] = [:]
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = APIClient.url(baseURL: baseURL, path: path) else {
            throw AuthAPIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(MealRoutineConfig.clientAPIVersion, forHTTPHeaderField: "X-Client-API-Version")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthAPIError.transport }
            return (data, http)
        } catch let error as AuthAPIError {
            throw error
        } catch {
            throw AuthAPIError.transport
        }
    }

    static func url(baseURL: URL, path: String) -> URL? {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: suffix, relativeTo: baseURL)?.absoluteURL
    }

    static func message(for code: String?) -> String {
        if let regional = code.flatMap({ RegionalErrorCode(rawValue: $0) }) {
            return regional.message
        }
        switch code {
        case "rate_limited":
            return AuthAPIError.rateLimited.message
        case "not_implemented":
            return L10n.text("api.error.notImplemented", "Sunucu bu işlemi henüz uygulamıyor.")
        case "invalid_request":
            return L10n.text("api.error.invalidRequest", "İstek tamamlanamadı.")
        default:
            return L10n.text("api.error.generic", "Sunucu isteği tamamlayamadı.")
        }
    }
}

private struct RefreshPayload: Encodable {
    var refreshToken: String
}

struct AccountRepository {
    var client: APIClient

    func signInWithApple(identityToken: String, givenName: String?, familyName: String?) async throws -> AuthSessionDTO {
        try await post(
            "/v1/auth/apple",
            body: AppleSignInBody(identityToken: identityToken, givenName: givenName, familyName: familyName),
            authenticated: false
        )
    }

    func signInWithGoogle(identityToken: String) async throws -> AuthSessionDTO {
        try await post("/v1/auth/google", body: GoogleSignInBody(identityToken: identityToken), authenticated: false)
    }

    func signInDev(subject: String, displayName: String) async throws -> AuthSessionDTO {
        try await post("/v1/auth/dev", body: DevSignInBody(subject: subject, displayName: displayName), authenticated: false)
    }

    func link(provider: String, identityToken: String, givenName: String?, familyName: String?) async throws -> AuthSessionDTO {
        try await post(
            "/v1/auth/link",
            body: LinkBody(provider: provider, identityToken: identityToken, givenName: givenName, familyName: familyName),
            authenticated: true
        )
    }

    func unlink(provider: String) async throws -> AuthSessionDTO {
        let (data, response) = try await client.request(
            method: "DELETE",
            path: "/v1/auth/identities/\(provider)",
            body: nil,
            authenticated: true
        )
        try client.validateAuth(response, data: data, authenticated: true)
        return try JSONDecoder().decode(AuthSessionDTO.self, from: data)
    }

    func me() async throws -> AuthMeDTO {
        let (data, response) = try await client.request(method: "GET", path: "/v1/auth/me", body: nil, authenticated: true)
        try client.validateAuth(response, data: data, authenticated: true)
        return try JSONDecoder().decode(AuthMeDTO.self, from: data)
    }

    func accountSettings() async throws -> RegionalSettings {
        let (data, response) = try await client.request(method: "GET", path: "/v1/account/settings", body: nil, authenticated: true)
        try client.validateAuth(response, data: data, authenticated: true)
        return try JSONDecoder().decode(AccountSettingsDTO.self, from: data).settings
    }

    /// Sends only the fields in `patch`; the server keeps the rest.
    func updateAccountSettings(_ patch: RegionalSettingsPatch) async throws -> RegionalSettings {
        let body = try JSONEncoder().encode(patch)
        let (data, response) = try await client.request(method: "PATCH", path: "/v1/account/settings", body: body, authenticated: true)
        try client.validateAuth(response, data: data, authenticated: true)
        return try JSONDecoder().decode(AccountSettingsDTO.self, from: data).settings
    }

    func logout(refreshToken: String) async {
        let body = try? JSONEncoder().encode(RefreshPayload(refreshToken: refreshToken))
        _ = try? await client.request(method: "POST", path: "/v1/auth/logout", body: body, authenticated: false)
    }

    func exportData() async throws -> Data {
        let (data, response) = try await client.request(
            method: "GET",
            path: "/v1/account/export",
            body: nil,
            authenticated: true
        )
        try client.validateAuth(response, data: data, authenticated: true)
        return data
    }

    func deleteAccount() async throws -> AccountDeletionResult {
        let (data, response) = try await client.request(
            method: "DELETE",
            path: "/v1/account",
            body: nil,
            authenticated: true
        )
        try client.validateAuth(response, data: data, authenticated: true)
        return try JSONDecoder().decode(AccountDeletionResult.self, from: data)
    }

    private func post<Body: Encodable>(_ path: String, body: Body, authenticated: Bool) async throws -> AuthSessionDTO {
        let data = try JSONEncoder().encode(body)
        let (responseData, response) = try await client.request(method: "POST", path: path, body: data, authenticated: authenticated)
        try client.validateAuth(response, data: responseData, authenticated: authenticated)
        return try JSONDecoder().decode(AuthSessionDTO.self, from: responseData)
    }
}

struct PantryListDTO: Decodable, Sendable { var items: [PantryRemoteItem]; var serverTime: String? }

struct PantryReconcileResponse: Decodable, Sendable {
    var lines: [PantryReconcileResultLine]
    var items: [PantryRemoteItem]
}

struct PantryReconcileResultLine: Decodable, Sendable {
    var ingredientId: String
    var resolvedIngredientId: String?
    var quantity: Double
    var unit: String
    var incompatible: Bool
    var unknownIngredient: Bool?
    var applied: Bool
}

/// `GET /v1/ingredients` row. `scope` is `dictionary` for the seed and `household` for user-created rows.
/// Named apart from the catalog `IngredientDTO` in `RecipeCatalogDTO.swift`.
/// `names` / `aliases` are keyed by locale; `displayName` / `synonyms` are the same data resolved
/// for the requested locale (and the only fields a pre-V5.1 server sends).
struct DictionaryIngredientDTO: Decodable, Sendable {
    var id: String
    var names: [String: String]?
    var aliases: [String: [String]]?
    var displayName: String
    var synonyms: [String]
    var sourceIds: [String]
    var scope: String

    var entry: IngredientEntry {
        if let names, !names.isEmpty {
            return IngredientEntry(id: id, names: names, aliases: aliases ?? [:], sourceIds: sourceIds)
        }
        return IngredientEntry(id: id, name: displayName, synonyms: synonyms, sourceIds: sourceIds, locale: IngredientEntry.sourceLocale)
    }
}

private struct IngredientListDTO: Decodable { var version: Int; var locale: String?; var ingredients: [DictionaryIngredientDTO] }
private struct IngredientRegisterBody: Encodable { var id: String; var displayName: String; var locale: String }

struct PantryRepository {
    var client: APIClient

    func list(householdId: UUID) async throws -> [PantryRemoteItem] {
        let (data, response) = try await client.request(method: "GET", path: "\(base(householdId))/pantry", body: nil, authenticated: true)
        try throwPantry(response, data: data)
        return try JSONDecoder.mealRoutine.decode(PantryListDTO.self, from: data).items
    }

    /// Dictionary plus this household's own ingredients. The server copy is authoritative.
    func ingredients(householdId: UUID?, query: String = "", limit: Int = 1000) async throws -> [DictionaryIngredientDTO] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let householdId { items.append(URLQueryItem(name: "householdId", value: householdId.uuidString.lowercased())) }
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        items.append(URLQueryItem(name: "locale", value: RegionalContext.contentLocale))
        var components = URLComponents()
        components.path = "/v1/ingredients"
        components.queryItems = items
        let (data, response) = try await client.request(method: "GET", path: components.string ?? "/v1/ingredients", body: nil, authenticated: true)
        try throwPantry(response, data: data)
        return try JSONDecoder.mealRoutine.decode(IngredientListDTO.self, from: data).ingredients
    }

    /// Registers a `custom:<uuid>` ingredient. Repeating the call with the same id is a no-op on the server.
    func registerIngredient(householdId: UUID, id: String, displayName: String, idempotencyKey: String) async throws -> DictionaryIngredientDTO {
        let body = try JSONEncoder.mealRoutine.encode(IngredientRegisterBody(id: id, displayName: displayName, locale: RegionalContext.contentLocale))
        let (data, response) = try await client.request(method: "POST", path: "\(base(householdId))/ingredients", body: body, authenticated: true, headers: ["Idempotency-Key": idempotencyKey])
        try throwPantry(response, data: data)
        return try JSONDecoder.mealRoutine.decode(DictionaryIngredientDTO.self, from: data)
    }

    func create(householdId: UUID, item: PantryRemoteItem, idempotencyKey: String, confirmSeparate: Bool = false) async throws -> PantryRemoteItem {
        let body = try JSONEncoder.mealRoutine.encode(PantryItemBody.create(item, confirmSeparate: confirmSeparate))
        return try await send("POST", "\(base(householdId))/pantry/items", body: body, idempotencyKey: idempotencyKey)
    }

    func update(householdId: UUID, item: PantryRemoteItem, baseVersion: Int, idempotencyKey: String) async throws -> PantryRemoteItem {
        let body = try JSONEncoder.mealRoutine.encode(PantryItemBody.patch(item))
        return try await send("PATCH", "\(itemPath(householdId, item.id))?baseVersion=\(max(1, baseVersion))", body: body, idempotencyKey: idempotencyKey)
    }

    func delete(householdId: UUID, itemId: UUID, baseVersion: Int?, idempotencyKey: String) async throws {
        var path = itemPath(householdId, itemId)
        if let baseVersion { path += "?baseVersion=\(max(1, baseVersion))" }
        let (data, response) = try await client.request(method: "DELETE", path: path, body: nil, authenticated: true, headers: ["Idempotency-Key": idempotencyKey])
        try throwPantry(response, data: data)
    }

    func reconcile(householdId: UUID, operation: String, lines: [PantryReconcileLine], idempotencyKey: String, confirmSeparate: Bool = false) async throws -> PantryReconcileResponse {
        let body = try JSONEncoder.mealRoutine.encode(PantryReconcileBody(operation: operation, confirmSeparate: confirmSeparate, lines: lines))
        let (data, response) = try await client.request(method: "POST", path: "\(base(householdId))/pantry/reconcile-grocery", body: body, authenticated: true, headers: ["Idempotency-Key": idempotencyKey])
        try throwPantry(response, data: data)
        return try JSONDecoder.mealRoutine.decode(PantryReconcileResponse.self, from: data)
    }

    private func base(_ householdId: UUID) -> String { "/v1/households/\(householdId.uuidString.lowercased())" }

    private func itemPath(_ householdId: UUID, _ itemId: UUID) -> String { "\(base(householdId))/pantry/items/\(itemId.uuidString.lowercased())" }

    private func send(_ method: String, _ path: String, body: Data, idempotencyKey: String) async throws -> PantryRemoteItem {
        let (data, response) = try await client.request(method: method, path: path, body: body, authenticated: true, headers: ["Idempotency-Key": idempotencyKey])
        try throwPantry(response, data: data)
        return try JSONDecoder.mealRoutine.decode(PantryRemoteItem.self, from: data)
    }

    /// Classified pantry errors first; anything transient falls through to the shared auth handling.
    private func throwPantry(_ response: HTTPURLResponse, data: Data) throws {
        if (200..<300).contains(response.statusCode) { return }
        let body = try? JSONDecoder.mealRoutine.decode(PantryErrorBody.self, from: data)
        if let classified = PantrySyncError.classify(status: response.statusCode, body: body) { throw classified }
        try client.validateAuth(response, data: data, authenticated: true)
        throw PantrySyncError.failed
    }
}

private struct PantryReconcileBody: Encodable {
    var operation: String
    var confirmSeparate: Bool
    var lines: [PantryReconcileLine]
}

private extension JSONEncoder { static var mealRoutine: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
private extension JSONDecoder {
    static var mealRoutine: JSONDecoder {
        let decoder = JSONDecoder()
        PantryServerClock.install(on: decoder)
        return decoder
    }
}

private struct AppleSignInBody: Encodable {
    var identityToken: String
    var givenName: String?
    var familyName: String?
}

private struct GoogleSignInBody: Encodable {
    var identityToken: String
}

private struct DevSignInBody: Encodable {
    var subject: String
    var displayName: String
}

private struct LinkBody: Encodable {
    var provider: String
    var identityToken: String
    var givenName: String?
    var familyName: String?
}

struct ProductEventUploader {
    var client: APIClient
    var defaults: UserDefaults

    func flushEvents() async -> Int {
        guard !ProductEventQueue.isOptedOut(defaults: defaults) else { return 0 }
        let batch = ProductEventQueue.nextBatch(defaults: defaults)
        guard !batch.isEmpty else { return 0 }
        do {
            let body = try JSONEncoder().encode(ProductEventBatch(events: batch))
            let (data, response) = try await client.request(
                method: "POST",
                path: "/v1/analytics/events",
                body: body,
                authenticated: true
            )
            try client.validateAuth(response, data: data, authenticated: true)
            ProductEventQueue.markSent(batch.map(\.id), defaults: defaults)
            return batch.count
        } catch {
            return 0
        }
    }

    func flushDiagnostics() async -> Int {
        guard DiagnosticQueue.allowsUpload(defaults: defaults) else { return 0 }
        let reports = DiagnosticQueue.pending(defaults: defaults)
        guard !reports.isEmpty else { return 0 }
        do {
            let body = try JSONEncoder().encode(DiagnosticBatch(reports: reports))
            let (data, response) = try await client.request(
                method: "POST",
                path: "/v1/diagnostics",
                body: body,
                authenticated: true
            )
            try client.validateAuth(response, data: data, authenticated: true)
            DiagnosticQueue.markSent(defaults: defaults)
            return reports.count
        } catch {
            return 0
        }
    }
}

@MainActor
enum ProductEventSync {
    static func installIfNeeded() {
        guard !HouseholdTestMode.shared.isEnabled else {
            Analytics.resetProductSinkForTests()
            return
        }
        Analytics.setProductSink { name, properties in
            ProductEventQueue.enqueue(name: name, properties: properties)
        }
        CrashReportCollector.shared.start()
    }

    static func flushIfAllowed() async {
        guard !HouseholdTestMode.shared.isEnabled else { return }
        guard let baseURL = MealRoutineConfig.apiBaseURL else { return }
        guard AuthServices.sharedTokens.load() != nil else { return }
        let client = APIClient(
            baseURL: baseURL,
            tokens: AuthServices.sharedTokens,
            refreshGate: AuthServices.refreshGate,
            expiry: AuthServices.expiry
        )
        let uploader = ProductEventUploader(client: client, defaults: .standard)
        _ = await uploader.flushEvents()
        _ = await uploader.flushDiagnostics()
    }
}

final class CrashReportCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReportCollector()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard DiagnosticQueue.allowsUpload() else { return }
        guard !payloads.isEmpty else { return }
        DiagnosticQueue.enqueue(DiagnosticReport(kind: "metric", count: min(payloads.count, 1_000), exceptionType: nil, signal: nil))
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard DiagnosticQueue.allowsUpload() else { return }
        for payload in payloads {
            enqueue(kind: "crash", count: payload.crashDiagnostics?.count ?? 0, diagnostic: payload.crashDiagnostics?.first)
            enqueueCount("hang", payload.hangDiagnostics?.count ?? 0)
            enqueueCount("cpu", payload.cpuExceptionDiagnostics?.count ?? 0)
            enqueueCount("disk", payload.diskWriteExceptionDiagnostics?.count ?? 0)
        }
    }

    private func enqueue(kind: String, count: Int, diagnostic: MXCrashDiagnostic?) {
        guard count > 0 else { return }
        DiagnosticQueue.enqueue(DiagnosticReport(
            kind: kind,
            count: min(count, 1_000),
            exceptionType: DiagnosticQueue.shortToken(diagnostic?.exceptionType?.stringValue),
            signal: DiagnosticQueue.shortToken(diagnostic?.signal?.stringValue)
        ))
    }

    private func enqueueCount(_ kind: String, _ count: Int) {
        guard count > 0 else { return }
        DiagnosticQueue.enqueue(DiagnosticReport(kind: kind, count: min(count, 1_000), exceptionType: nil, signal: nil))
    }
}
