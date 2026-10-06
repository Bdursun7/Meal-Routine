import Foundation
import Security

protocol TokenStoring: Sendable {
    func load() -> AuthTokenSet?
    func save(_ tokens: AuthTokenSet)
    func clear()
}

final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokenSet?

    func load() -> AuthTokenSet? {
        lock.lock()
        defer { lock.unlock() }
        return tokens
    }

    func save(_ tokens: AuthTokenSet) {
        lock.lock()
        defer { lock.unlock() }
        self.tokens = tokens
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        tokens = nil
    }
}

struct KeychainTokenStore: TokenStoring {
    var service: String

    init(service: String = "com.mealroutine.app.auth") {
        self.service = service
    }

    func load() -> AuthTokenSet? {
        let query = baseQuery(returningData: true)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokenSet.self, from: data)
    }

    func save(_ tokens: AuthTokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query = baseQuery(returningData: false)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            for (key, value) in attributes {
                insert[key] = value
            }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(baseQuery(returningData: false) as CFDictionary)
    }

    private func baseQuery(returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session",
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

/// Notifies the UI when a refresh token is rejected. The handler must not log tokens.
final class SessionExpiryCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func setHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func emit() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}

enum AuthServices {
    static let sharedTokens: any TokenStoring = KeychainTokenStore()
    static let refreshGate = RefreshGate()
    static let expiry = SessionExpiryCenter()
}
