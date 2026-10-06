import Foundation

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

    func request(method: String, path: String, body: Data?, authenticated: Bool) async throws -> (Data, HTTPURLResponse) {
        let access = try await accessToken(authenticated: authenticated)
        let first = try await perform(method: method, path: path, body: body, accessToken: access)
        guard authenticated, first.response.statusCode == 401 else {
            return (first.data, first.response)
        }
        guard let current = tokens.load() else {
            expiry.emit()
            throw AuthAPIError.sessionExpired
        }
        let refreshed = try await refresh(current, force: true)
        let second = try await perform(method: method, path: path, body: body, accessToken: refreshed.accessToken)
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

    private func perform(method: String, path: String, body: Data?, accessToken: String?) async throws -> (data: Data, response: HTTPURLResponse) {
        try await APIClient.perform(
            session: session,
            baseURL: baseURL,
            method: method,
            path: path,
            body: body,
            accessToken: accessToken
        )
    }

    private static func perform(
        session: URLSession,
        baseURL: URL,
        method: String,
        path: String,
        body: Data?,
        accessToken: String?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = APIClient.url(baseURL: baseURL, path: path) else {
            throw AuthAPIError.transport
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(MealRoutineConfig.clientAPIVersion, forHTTPHeaderField: "X-Client-API-Version")
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

    private static func message(for code: String?) -> String {
        switch code {
        case "rate_limited":
            AuthAPIError.rateLimited.message
        case "not_implemented":
            "Sunucu bu işlemi henüz uygulamıyor."
        case "invalid_request":
            "İstek tamamlanamadı."
        default:
            "Sunucu isteği tamamlayamadı."
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

    func logout(refreshToken: String) async {
        let body = try? JSONEncoder().encode(RefreshPayload(refreshToken: refreshToken))
        _ = try? await client.request(method: "POST", path: "/v1/auth/logout", body: body, authenticated: false)
    }

    private func post<Body: Encodable>(_ path: String, body: Body, authenticated: Bool) async throws -> AuthSessionDTO {
        let data = try JSONEncoder().encode(body)
        let (responseData, response) = try await client.request(method: "POST", path: path, body: data, authenticated: authenticated)
        try client.validateAuth(response, data: responseData, authenticated: authenticated)
        return try JSONDecoder().decode(AuthSessionDTO.self, from: responseData)
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
