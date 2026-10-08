import Foundation

struct AuthTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var accessExpiresAt: Date
    var accountId: String
    var displayName: String
}

enum TokenRefreshPolicy {
    /// Refresh a little before the access token actually expires.
    static let skew: TimeInterval = 60

    static func needsRefresh(accessExpiresAt: Date, now: Date, skew: TimeInterval = TokenRefreshPolicy.skew) -> Bool {
        accessExpiresAt.timeIntervalSince(now) <= skew
    }
}

enum AuthAPIError: Error, Equatable {
    case linkRequired(existingProviders: [String])
    case sessionExpired
    case rateLimited
    case googleClientMissing
    case server(String)
    case transport

    var message: String {
        switch self {
        case .linkRequired(let providers):
            let names = providers.map(AuthProviderLabel.title).joined(separator: ", ")
            if names.isEmpty {
                return "Bu giriş mevcut bir MealRoutine hesabıyla eşleşiyor. Önce o hesapla gir, sonra diğerini Hesap ekranından bağla."
            }
            return "Bu e-posta \(names) hesabına ait. Önce onunla gir, sonra diğer sağlayıcıyı Hesap ekranından bağla. İkinci hesap açılmaz."
        case .sessionExpired:
            return "Oturumun sona erdi. Tekrar giriş yap."
        case .rateLimited:
            return "Çok fazla deneme oldu. Bir dakika sonra tekrar dene."
        case .googleClientMissing:
            return MealRoutineConfig.googleClientMissingMessage
        case .server(let detail):
            return detail
        case .transport:
            return "Sunucuya ulaşılamadı."
        }
    }
}

enum AuthProviderLabel {
    static func title(_ provider: String) -> String {
        switch provider {
        case "apple": "Apple"
        case "google": "Google"
        case "dev": "Yerel test"
        default: provider
        }
    }
}

struct AuthAccountDTO: Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var givenName: String
    var familyName: String
}

struct AuthIdentityDTO: Codable, Equatable, Sendable, Identifiable {
    var provider: String
    var email: String?
    var isPrivateRelay: Bool

    var id: String { provider }
}

struct AuthSessionDTO: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var account: AuthAccountDTO
    var identities: [AuthIdentityDTO]
    /// Absent from pre-5.1 servers.
    var settings: RegionalSettings? = nil
}

struct AuthMeDTO: Codable, Equatable, Sendable {
    var account: AuthAccountDTO
    var identities: [AuthIdentityDTO]
    var settings: RegionalSettings? = nil
}

struct AccountSettingsDTO: Codable, Equatable, Sendable {
    var settings: RegionalSettings
}
struct APIErrorDTO: Codable, Equatable, Sendable {
    var error: String
    var existingProviders: [String]?
}

struct AccountDeletionResult: Codable, Equatable, Sendable {
    var deleted: Bool
    var household: String
}

enum AccountPrivacyCopy {
    static let confirmTitle = "Hesabını silmek istiyor musun?"
    static let confirmBody = "Kişisel tariflerin, yemek hafızan, kişisel evdekiler ve girişlerin silinir. Ortak evde bir partner kalırsa ev ve evdekiler ona kalır. Son üye ev halkını kapatınca evdekiler de silinir. Bu işlem geri alınamaz."
    static let deleteButton = "Hesabımı sil"
    static let cancelButton = "Vazgeç"
    static let exportButton = "Verilerimi indir"
    static let deleted = "Hesabın silindi. Kişisel verilerin sunucudan kaldırıldı."
    static let exported = "Verilerin hazır. Paylaşmak için dosyayı aç."
}

enum AccountPrivacySession {
    static func clearTokens(_ tokens: any TokenStoring) {
        tokens.clear()
    }
}

enum DevSubjectStore {
    private static let key = "mealroutine.devSubject"

    static func subject(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 3 {
            return existing
        }
        let created = "dev-\(UUID().uuidString.lowercased())"
        defaults.set(created, forKey: key)
        return created
    }
}
