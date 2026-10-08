import { AppError } from './errors.js'

/**
 * Regional context for accounts and households. Locale, country, currency, measurement system
 * and timezone are independent codes: none of them is derived from another, and none is
 * inferred from an email domain or sign-in provider.
 */
export type MeasurementSystem = 'metric' | 'imperial'

export interface UserRegionalSettings {
  locale: string
  countryCode: string
  currencyCode: string
  measurementSystem: MeasurementSystem
  timezone: string
}

export interface HouseholdRegionalSettings {
  countryCode: string
  currencyCode: string
  measurementSystem: MeasurementSystem
  timezone: string
}

/**
 * Deterministic defaults for the first (Turkey) deployment. These are migration and fallback
 * values only; `0013_globalization.sql` uses the same literals. Business logic never compares
 * against them.
 */
export const REGIONAL_DEFAULTS: Readonly<UserRegionalSettings> = Object.freeze({
  locale: 'tr-TR',
  countryCode: 'TR',
  currencyCode: 'TRY',
  measurementSystem: 'metric',
  timezone: 'Europe/Istanbul',
})

/** Locales the product accepts as a stored preference. The shipped UI is still only tr-TR. */
export const SUPPORTED_LOCALES: readonly string[] = Object.freeze(['tr-TR', 'en-US', 'en-GB', 'de-DE', 'fr-FR'])

export const MEASUREMENT_SYSTEMS: readonly MeasurementSystem[] = Object.freeze(['metric', 'imperial'])

/** ISO 3166-1 alpha-2, officially assigned codes only (no reserved or legacy codes). */
export const ISO_COUNTRY_CODES: ReadonlySet<string> = new Set(
  (
    'AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ ' +
    'CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR ' +
    'GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP ' +
    'KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT ' +
    'MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW ' +
    'SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG ' +
    'UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'
  ).split(' '),
)

/** ISO 4217 codes in current circulation (fund and precious-metal codes excluded). */
export const ISO_CURRENCY_CODES: ReadonlySet<string> = new Set(
  (
    'AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF ' +
    'CLP CNY COP CRC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF ' +
    'IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK ' +
    'MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR ' +
    'SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VES ' +
    'VND VUV WST XAF XCD XCG XOF XPF YER ZAR ZMW ZWG'
  ).split(' '),
)

export const REGIONAL_ERROR_CODES = Object.freeze([
  'unsupported_locale',
  'invalid_currency',
  'invalid_measurement_system',
  'invalid_timezone',
  'invalid_country',
] as const)

export type RegionalErrorCode = (typeof REGIONAL_ERROR_CODES)[number]

function fail(code: RegionalErrorCode, field: string): never {
  throw new AppError(code, 400, undefined, { field })
}

export function validLocale(value: unknown): string {
  if (typeof value !== 'string' || !SUPPORTED_LOCALES.includes(value)) fail('unsupported_locale', 'locale')
  return value
}

export function validCountry(value: unknown): string {
  if (typeof value !== 'string' || !ISO_COUNTRY_CODES.has(value)) fail('invalid_country', 'countryCode')
  return value
}

export function validCurrency(value: unknown): string {
  if (typeof value !== 'string' || !ISO_CURRENCY_CODES.has(value)) fail('invalid_currency', 'currencyCode')
  return value
}

export function validMeasurementSystem(value: unknown): MeasurementSystem {
  if (typeof value !== 'string' || !MEASUREMENT_SYSTEMS.includes(value as MeasurementSystem)) {
    fail('invalid_measurement_system', 'measurementSystem')
  }
  return value as MeasurementSystem
}

const TIMEZONE_SHAPE = /^(UTC|[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+)+)$/

/** IANA zone name (`Europe/Istanbul`, `UTC`). Raw offsets such as `+03:00` are not timezones. */
export function validTimezone(value: unknown): string {
  if (typeof value !== 'string' || value.length > 64 || !TIMEZONE_SHAPE.test(value)) fail('invalid_timezone', 'timezone')
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value })
  } catch {
    fail('invalid_timezone', 'timezone')
  }
  return value
}

type Partialish<T> = { [K in keyof T]?: unknown }

/** Validates only the fields that are present. Field order is fixed so the first error is deterministic. */
export function validateUserSettingsPatch(input: Partialish<UserRegionalSettings>): Partial<UserRegionalSettings> {
  const out: Partial<UserRegionalSettings> = {}
  if (input.locale !== undefined) out.locale = validLocale(input.locale)
  if (input.countryCode !== undefined) out.countryCode = validCountry(input.countryCode)
  if (input.currencyCode !== undefined) out.currencyCode = validCurrency(input.currencyCode)
  if (input.measurementSystem !== undefined) out.measurementSystem = validMeasurementSystem(input.measurementSystem)
  if (input.timezone !== undefined) out.timezone = validTimezone(input.timezone)
  return out
}

export function validateHouseholdSettingsPatch(input: Partialish<HouseholdRegionalSettings>): Partial<HouseholdRegionalSettings> {
  const out: Partial<HouseholdRegionalSettings> = {}
  if (input.countryCode !== undefined) out.countryCode = validCountry(input.countryCode)
  if (input.currencyCode !== undefined) out.currencyCode = validCurrency(input.currencyCode)
  if (input.measurementSystem !== undefined) out.measurementSystem = validMeasurementSystem(input.measurementSystem)
  if (input.timezone !== undefined) out.timezone = validTimezone(input.timezone)
  return out
}

export function defaultUserSettings(): UserRegionalSettings {
  return { ...REGIONAL_DEFAULTS }
}

/** Stored settings of an account; rows that predate the columns read as the migration defaults. */
export function accountRegional(account: { regional?: UserRegionalSettings }): UserRegionalSettings {
  return account.regional ? { ...account.regional } : defaultUserSettings()
}

/**
 * A new household copies the creator's own context for each field the request leaves out.
 * Each field copies the same concept; nothing is derived across concepts.
 */
export function householdSettingsFrom(
  creator: UserRegionalSettings,
  requested: Partial<HouseholdRegionalSettings>,
): HouseholdRegionalSettings {
  return {
    countryCode: requested.countryCode ?? creator.countryCode,
    currencyCode: requested.currencyCode ?? creator.currencyCode,
    measurementSystem: requested.measurementSystem ?? creator.measurementSystem,
    timezone: requested.timezone ?? creator.timezone,
  }
}

// MARK: Week identity

const DATE_TEXT = /^(\d{4})-(\d{2})-(\d{2})$/

/** Calendar date (`YYYY-MM-DD`) of an instant as seen in `timezone`. */
export function localDate(instant: Date, timezone: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(instant)
  const pick = (type: string) => parts.find((part) => part.type === type)?.value ?? ''
  return `${pick('year')}-${pick('month')}-${pick('day')}`
}

function civilDays(text: string): number | null {
  const match = DATE_TEXT.exec(text)
  if (!match) return null
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])]
  const ms = Date.UTC(year, month - 1, day)
  const check = new Date(ms)
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) return null
  return Math.floor(ms / 86_400_000)
}

function civilText(days: number): string {
  return new Date(days * 86_400_000).toISOString().slice(0, 10)
}

/** ISO weekday of a calendar date: Monday 1 ... Sunday 7. Null for an invalid date. */
export function isoWeekday(dateText: string): number | null {
  const days = civilDays(dateText)
  if (days === null) return null
  // 1970-01-01 was a Thursday (ISO 4).
  return ((((days + 3) % 7) + 7) % 7) + 1
}

/**
 * Week identity: the Monday (`YYYY-MM-DD`) of the ISO week that contains `instant` in the
 * household timezone. Server UTC never decides which week an instant belongs to.
 */
export function weekStartFor(instant: Date, timezone: string): string {
  const today = localDate(instant, validTimezone(timezone))
  const days = civilDays(today)!
  const weekday = isoWeekday(today)!
  return civilText(days - (weekday - 1))
}

/** A shared plan's week identity must be a real calendar Monday. */
export function validWeekStart(value: string): string {
  if (isoWeekday(value) !== 1) throw new AppError('invalid_week_start', 400, undefined, { field: 'weekStart' })
  return value
}

/** UTC instant at which a week identity starts in `timezone` (local Monday 00:00). */
export function weekStartInstant(weekStart: string, timezone: string): Date {
  validWeekStart(weekStart)
  const days = civilDays(weekStart)!
  const zone = validTimezone(timezone)
  // Local midnight is within ±14h of UTC midnight; walk the offset until the local date matches.
  let guess = days * 86_400_000
  for (let step = 0; step < 3; step += 1) {
    const offset = zoneOffsetMs(new Date(guess), zone)
    const candidate = days * 86_400_000 - offset
    if (candidate === guess) break
    guess = candidate
  }
  return new Date(guess)
}

function zoneOffsetMs(instant: Date, timezone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(instant)
  const pick = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? '0')
  const asUtc = Date.UTC(pick('year'), pick('month') - 1, pick('day'), pick('hour'), pick('minute'), pick('second'))
  return asUtc - Math.floor(instant.getTime() / 1000) * 1000
}
