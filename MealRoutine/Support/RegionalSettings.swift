import Foundation

/// Metric or imperial. Chosen per user and per household; never inferred from the country.
enum MeasurementSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

/// A user's regional context. Every field is an independent code: none is derived from another,
/// and none is inferred from an email domain or sign-in provider.
struct RegionalSettings: Codable, Equatable, Hashable, Sendable {
    var locale: String
    var countryCode: String
    var currencyCode: String
    var measurementSystem: MeasurementSystem
    var timezone: String
}

/// A household's regional context. Week identity, pantry dates and (V6) prices use it.
struct HouseholdRegionalSettings: Codable, Equatable, Hashable, Sendable {
    var countryCode: String
    var currencyCode: String
    var measurementSystem: MeasurementSystem
    var timezone: String
}

/// The single place for first-deployment (Turkey) defaults. Server `REGIONAL_DEFAULTS` and
/// migration `0013` use the same values. Business logic never compares against them.
enum RegionalDefaults {
    static let locale = "tr-TR"
    static let countryCode = "TR"
    static let currencyCode = "TRY"
    static let measurementSystem = MeasurementSystem.metric
    static let timezone = "Europe/Istanbul"

    /// Locales accepted as a stored preference (same list as the server).
    static let supportedLocales = ["tr-TR", "en-US", "en-GB", "de-DE", "fr-FR"]
    /// Locales the shipped UI has translations for. Anything else displays in `uiFallbackLocale`.
    static let uiLocales = ["tr-TR"]
    static let uiFallbackLocale = "tr-TR"

    static var user: RegionalSettings {
        RegionalSettings(
            locale: locale,
            countryCode: countryCode,
            currencyCode: currencyCode,
            measurementSystem: measurementSystem,
            timezone: timezone
        )
    }

    static var household: HouseholdRegionalSettings {
        HouseholdRegionalSettings(
            countryCode: countryCode,
            currencyCode: currencyCode,
            measurementSystem: measurementSystem,
            timezone: timezone
        )
    }
}

/// Stable codes shared with the server (`regional.ts`). The UI maps them to localized text.
enum RegionalErrorCode: String, Codable, CaseIterable, Sendable, Error {
    case unsupportedLocale = "unsupported_locale"
    case invalidCurrency = "invalid_currency"
    case invalidMeasurementSystem = "invalid_measurement_system"
    case invalidTimezone = "invalid_timezone"
    case invalidCountry = "invalid_country"

    /// The user-facing sentence for a server or local validation code.
    var message: String {
        switch self {
        case .unsupportedLocale: L10n.text("regional.error.unsupportedLocale", "Bu dil ve bölge henüz desteklenmiyor.")
        case .invalidCurrency: L10n.text("regional.error.invalidCurrency", "Para birimi geçersiz.")
        case .invalidMeasurementSystem: L10n.text("regional.error.invalidMeasurementSystem", "Ölçü sistemi geçersiz.")
        case .invalidTimezone: L10n.text("regional.error.invalidTimezone", "Saat dilimi geçersiz.")
        case .invalidCountry: L10n.text("regional.error.invalidCountry", "Ülke kodu geçersiz.")
        }
    }
}

/// Same rules as the server. The code lists are static so iOS and Linux agree with the server;
/// `server/test/regional.test.ts` checks the lists below against `server/src/regional.ts`.
enum RegionalValidator {
    static func isSupportedLocale(_ value: String) -> Bool { RegionalDefaults.supportedLocales.contains(value) }

    static func isCountry(_ value: String) -> Bool { isoCountryCodes.contains(value) }

    static func isCurrency(_ value: String) -> Bool { isoCurrencyCodes.contains(value) }

    static func isMeasurementSystem(_ value: String) -> Bool { MeasurementSystem(rawValue: value) != nil }

    /// IANA zone name (`Europe/Istanbul`, `UTC`). Offsets such as `GMT+3` or `+03:00` are not timezones.
    static func isTimezone(_ value: String) -> Bool {
        guard value.count <= 64, value.range(of: timezoneShape, options: .regularExpression) != nil else { return false }
        return TimeZone(identifier: value) != nil
    }

    /// First failing field in the server's order, or nil when every field is valid.
    static func validate(_ settings: RegionalSettings) -> RegionalErrorCode? {
        if !isSupportedLocale(settings.locale) { return .unsupportedLocale }
        return validate(
            HouseholdRegionalSettings(
                countryCode: settings.countryCode,
                currencyCode: settings.currencyCode,
                measurementSystem: settings.measurementSystem,
                timezone: settings.timezone
            )
        )
    }

    static func validate(_ settings: HouseholdRegionalSettings) -> RegionalErrorCode? {
        if !isCountry(settings.countryCode) { return .invalidCountry }
        if !isCurrency(settings.currencyCode) { return .invalidCurrency }
        if !isTimezone(settings.timezone) { return .invalidTimezone }
        return nil
    }

    static let timezoneShape = "^(UTC|[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+)$"

    /// ISO 3166-1 alpha-2, officially assigned codes only.
    static let isoCountryCodes: Set<String> = Set((
        "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ " +
        "CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR " +
        "GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP " +
        "KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT " +
        "MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW " +
        "SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG " +
        "UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW"
    ).split(separator: " ").map(String.init))

    /// ISO 4217 codes in current circulation (fund and precious-metal codes excluded).
    static let isoCurrencyCodes: Set<String> = Set((
        "AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF " +
        "CLP CNY COP CRC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF " +
        "IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK " +
        "MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR " +
        "SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VES " +
        "VND VUV WST XAF XCD XCG XOF XPF YER ZAR ZMW ZWG"
    ).split(separator: " ").map(String.init))
}

/// The regional context the app is running in: the signed-in user's settings and, when there is
/// one, the active household's. Formatters and week identity read it; nothing reads the raw
/// device calendar or `TimeZone.current` for business decisions.
final class RegionalContext: @unchecked Sendable {
    static let shared = RegionalContext()

    private let lock = NSLock()
    private var userSettings: RegionalSettings
    private var householdSettings: HouseholdRegionalSettings?

    init(user: RegionalSettings = RegionalDefaults.user, household: HouseholdRegionalSettings? = nil) {
        userSettings = user
        householdSettings = household
    }

    var user: RegionalSettings {
        lock.lock(); defer { lock.unlock() }
        return userSettings
    }

    var household: HouseholdRegionalSettings? {
        lock.lock(); defer { lock.unlock() }
        return householdSettings
    }

    func apply(user: RegionalSettings) {
        lock.lock(); defer { lock.unlock() }
        userSettings = user
    }

    func apply(household: HouseholdRegionalSettings?) {
        lock.lock(); defer { lock.unlock() }
        householdSettings = household
    }

    /// Household timezone when in a household, otherwise the user's own.
    var timeZoneIdentifier: String {
        lock.lock(); defer { lock.unlock() }
        let identifier = householdSettings?.timezone ?? userSettings.timezone
        return RegionalValidator.isTimezone(identifier) ? identifier : RegionalDefaults.timezone
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    var currencyCode: String {
        lock.lock(); defer { lock.unlock() }
        return householdSettings?.currencyCode ?? userSettings.currencyCode
    }

    var measurementSystem: MeasurementSystem {
        lock.lock(); defer { lock.unlock() }
        return householdSettings?.measurementSystem ?? userSettings.measurementSystem
    }

    /// Locale for UI text and number/date formatting: the user's locale when the UI ships it.
    var displayLocaleIdentifier: String {
        lock.lock(); defer { lock.unlock() }
        return RegionalDefaults.uiLocales.contains(userSettings.locale) ? userSettings.locale : RegionalDefaults.uiFallbackLocale
    }

    var displayLocale: Locale { Locale(identifier: displayLocaleIdentifier) }

    /// Locale whose ingredient names and aliases the user types and reads.
    var contentLocale: String { displayLocaleIdentifier }

    /// Gregorian calendar in `timeZone`. Calendar days (pantry dates, "today") are read with it.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = displayLocale
        return calendar
    }

    static var timeZone: TimeZone { shared.timeZone }
    static var displayLocale: Locale { shared.displayLocale }
    static var contentLocale: String { shared.contentLocale }
    static var calendar: Calendar { shared.calendar }
}

/// Device values offered when a user or household is created. Only locale and timezone come from
/// the device; country, currency and measurement system stay at the configured defaults.
enum DeviceRegion {
    static func timezone(_ zone: TimeZone = .current) -> String {
        RegionalValidator.isTimezone(zone.identifier) ? zone.identifier : RegionalDefaults.timezone
    }

    static func locale(_ locale: Locale = .current) -> String {
        let base = locale.identifier.split(separator: "@").first.map(String.init) ?? ""
        let parts = base.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let language = parts.first,
              let region = parts.dropFirst().last(where: { $0.count == 2 && $0 == $0.uppercased() }) else {
            return RegionalDefaults.locale
        }
        let candidate = "\(language.lowercased())-\(region)"
        return RegionalValidator.isSupportedLocale(candidate) ? candidate : RegionalDefaults.locale
    }
}
