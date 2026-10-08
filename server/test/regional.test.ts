import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { FastifyInstance } from 'fastify'
import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { AppError } from '../src/errors.js'
import { buildIngredientIndex, makeIngredient, publicIngredient, resolveIngredientId, searchIngredients, seedIngredients } from '../src/ingredients.js'
import { notificationCopy } from '../src/notifications.js'
import { convertPantryQuantity, parsePantryUnit, PANTRY_UNIT_CODES, unitsCompatible } from '../src/pantryUnits.js'
import {
  householdSettingsFrom,
  ISO_COUNTRY_CODES,
  ISO_CURRENCY_CODES,
  SUPPORTED_LOCALES,
  isoWeekday,
  localDate,
  REGIONAL_DEFAULTS,
  validateHouseholdSettingsPatch,
  validateUserSettingsPatch,
  validWeekStart,
  weekStartFor,
  weekStartInstant,
} from '../src/regional.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

function codeOf(work: () => unknown): string | null {
  try {
    work()
    return null
  } catch (error) {
    return error instanceof AppError ? error.code : 'not-app-error'
  }
}

async function signIn(app: FastifyInstance, subject: string, extra: Record<string, unknown> = {}) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: { identityToken: identityToken({ subject, givenName: 'Ada', familyName: '', ...extra }), givenName: 'Ada' },
  })
  expect(response.statusCode).toBe(200)
  return { body: response.json(), auth: { authorization: `Bearer ${response.json().accessToken}` } }
}

describe('regional settings validation', () => {
  it('returns one stable error code per invalid field', () => {
    expect(codeOf(() => validateUserSettingsPatch({ locale: 'tr' }))).toBe('unsupported_locale')
    expect(codeOf(() => validateUserSettingsPatch({ locale: 'xx-XX' }))).toBe('unsupported_locale')
    expect(codeOf(() => validateUserSettingsPatch({ countryCode: 'tr' }))).toBe('invalid_country')
    expect(codeOf(() => validateUserSettingsPatch({ countryCode: 'XK' }))).toBe('invalid_country')
    expect(codeOf(() => validateUserSettingsPatch({ currencyCode: 'TL' }))).toBe('invalid_currency')
    expect(codeOf(() => validateUserSettingsPatch({ currencyCode: '₺' }))).toBe('invalid_currency')
    expect(codeOf(() => validateUserSettingsPatch({ measurementSystem: 'us' }))).toBe('invalid_measurement_system')
    expect(codeOf(() => validateUserSettingsPatch({ timezone: '+03:00' }))).toBe('invalid_timezone')
    expect(codeOf(() => validateUserSettingsPatch({ timezone: 'Mars/Olympus' }))).toBe('invalid_timezone')
    expect(codeOf(() => validateUserSettingsPatch({ timezone: 42 }))).toBe('invalid_timezone')
    expect(codeOf(() => validateHouseholdSettingsPatch({ countryCode: 'US', currencyCode: 'XYZ', timezone: 'bad' }))).toBe('invalid_currency')
  })

  it('accepts supported values and keeps fields independent', () => {
    expect(validateUserSettingsPatch({ locale: 'en-US', countryCode: 'TR', currencyCode: 'EUR', measurementSystem: 'imperial', timezone: 'Pacific/Auckland' })).toEqual({
      locale: 'en-US',
      countryCode: 'TR',
      currencyCode: 'EUR',
      measurementSystem: 'imperial',
      timezone: 'Pacific/Auckland',
    })
    expect(validateHouseholdSettingsPatch({ timezone: 'UTC' })).toEqual({ timezone: 'UTC' })
    expect(householdSettingsFrom({ ...REGIONAL_DEFAULTS, timezone: 'America/Los_Angeles' }, { currencyCode: 'USD' })).toEqual({
      countryCode: 'TR',
      currencyCode: 'USD',
      measurementSystem: 'metric',
      timezone: 'America/Los_Angeles',
    })
  })

  it('has the Turkey defaults in one place', () => {
    expect(REGIONAL_DEFAULTS).toEqual({ locale: 'tr-TR', countryCode: 'TR', currencyCode: 'TRY', measurementSystem: 'metric', timezone: 'Europe/Istanbul' })
    expect(Object.isFrozen(REGIONAL_DEFAULTS)).toBe(true)
  })
})

describe('iOS parity', () => {
  const swift = readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../MealRoutine/Support/RegionalSettings.swift'), 'utf8')
  const block = (name: string) => {
    const start = swift.indexOf(`static let ${name}`)
    const body = swift.slice(start, swift.indexOf('.split(separator', start))
    return new Set([...body.matchAll(/"([^"]*)"/g)].flatMap((match) => match[1]!.trim().split(/\s+/)).filter(Boolean))
  }

  it('uses the same code lists and defaults as RegionalSettings.swift', () => {
    expect([...block('isoCountryCodes')].sort()).toEqual([...ISO_COUNTRY_CODES].sort())
    expect([...block('isoCurrencyCodes')].sort()).toEqual([...ISO_CURRENCY_CODES].sort())
    const locales = /static let supportedLocales = \[([^\]]*)\]/.exec(swift)![1]!
    expect([...locales.matchAll(/"([^"]+)"/g)].map((match) => match[1])).toEqual([...SUPPORTED_LOCALES])
    for (const [field, value] of Object.entries(REGIONAL_DEFAULTS)) {
      const swiftValue = field === 'measurementSystem' ? `MeasurementSystem.${value}` : `"${value}"`
      expect(swift, field).toContain(`static let ${field} = ${swiftValue}`)
    }
    expect(swift).toContain('static let timezoneShape = "^(UTC|[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)+)$"')
  })
})

describe('week identity in the household timezone', () => {
  it('uses the local Monday, not the server UTC day', () => {
    const instant = new Date('2030-06-02T21:00:00Z')
    expect(weekStartFor(instant, 'Europe/Istanbul')).toBe('2030-06-03')
    expect(weekStartFor(instant, 'America/Los_Angeles')).toBe('2030-05-27')
    expect(weekStartFor(instant, 'Pacific/Auckland')).toBe('2030-06-03')
    expect(weekStartFor(instant, 'UTC')).toBe('2030-05-27')
    expect(weekStartFor(new Date('2030-06-02T20:59:59Z'), 'Europe/Istanbul')).toBe('2030-05-27')
  })

  it('is deterministic across DST changes', () => {
    // America/Los_Angeles springs forward on Sunday 2030-03-10 and falls back on Sunday 2030-11-03.
    expect(weekStartFor(new Date('2030-03-11T06:59:59Z'), 'America/Los_Angeles')).toBe('2030-03-04')
    expect(weekStartFor(new Date('2030-03-11T07:00:00Z'), 'America/Los_Angeles')).toBe('2030-03-11')
    expect(weekStartInstant('2030-03-04', 'America/Los_Angeles').toISOString()).toBe('2030-03-04T08:00:00.000Z')
    expect(weekStartInstant('2030-03-11', 'America/Los_Angeles').toISOString()).toBe('2030-03-11T07:00:00.000Z')
    expect(weekStartInstant('2030-11-04', 'America/Los_Angeles').toISOString()).toBe('2030-11-04T08:00:00.000Z')
    expect(weekStartFor(new Date('2030-11-04T07:59:59Z'), 'America/Los_Angeles')).toBe('2030-10-28')
    // Pacific/Auckland leaves daylight time on Sunday 2030-04-07 and enters it on Sunday 2030-09-29.
    expect(weekStartInstant('2030-04-01', 'Pacific/Auckland').toISOString()).toBe('2030-03-31T11:00:00.000Z')
    expect(weekStartInstant('2030-04-08', 'Pacific/Auckland').toISOString()).toBe('2030-04-07T12:00:00.000Z')
    expect(weekStartInstant('2030-09-30', 'Pacific/Auckland').toISOString()).toBe('2030-09-29T11:00:00.000Z')
    expect(weekStartFor(new Date('2030-04-07T11:59:59Z'), 'Pacific/Auckland')).toBe('2030-04-01')
    expect(weekStartFor(new Date('2030-04-07T12:00:00Z'), 'Pacific/Auckland')).toBe('2030-04-08')
    // Europe/Istanbul has no DST: Monday 00:00 is always 21:00Z on Sunday.
    expect(weekStartInstant('2030-01-07', 'Europe/Istanbul').toISOString()).toBe('2030-01-06T21:00:00.000Z')
    expect(weekStartInstant('2030-07-01', 'Europe/Istanbul').toISOString()).toBe('2030-06-30T21:00:00.000Z')
  })

  it('round-trips every week of a year in each zone', () => {
    for (const zone of ['Europe/Istanbul', 'America/Los_Angeles', 'Pacific/Auckland']) {
      let week = '2029-12-31'
      for (let index = 0; index < 53; index += 1) {
        const start = weekStartInstant(week, zone)
        expect(localDate(start, zone)).toBe(week)
        expect(weekStartFor(start, zone)).toBe(week)
        expect(weekStartFor(new Date(start.getTime() - 1000), zone)).not.toBe(week)
        const next = new Date(Date.UTC(Number(week.slice(0, 4)), Number(week.slice(5, 7)) - 1, Number(week.slice(8, 10)) + 7))
        week = next.toISOString().slice(0, 10)
      }
    }
  })

  it('accepts only real Mondays as a week identity', () => {
    expect(isoWeekday('2030-06-03')).toBe(1)
    expect(isoWeekday('2030-06-02')).toBe(7)
    expect(validWeekStart('2030-06-03')).toBe('2030-06-03')
    expect(codeOf(() => validWeekStart('2030-06-02'))).toBe('invalid_week_start')
    expect(codeOf(() => validWeekStart('2030-02-31'))).toBe('invalid_week_start')
  })
})

describe('locale-keyed ingredients', () => {
  const tomato = seedIngredients().find((row) => row.id === 'tomato')!

  it('carries names and aliases by locale on the wire', () => {
    const wire = publicIngredient(tomato, 'tr-TR')
    expect(wire.names).toEqual({ 'tr-TR': tomato.names['tr-TR'] })
    expect(Object.keys(wire.aliases)).toEqual(['tr-TR'])
    expect(wire.displayName).toBe(tomato.names['tr-TR'])
    expect(publicIngredient(tomato, 'en-US').displayName).toBe(tomato.names['tr-TR'])
  })

  it('never changes identity with the active locale', () => {
    const entries = [...seedIngredients(), makeIngredient({ id: 'custom:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', householdId: 'h', names: { 'en-US': 'Tomato paste' } })]
    const index = buildIngredientIndex(entries)
    expect(resolveIngredientId(index, 'import:domates')).toBe('tomato')
    expect(resolveIngredientId(index, 'import:tomato paste')).toBeNull()
    expect(searchIngredients(entries, 'domates', 5, 'tr-TR')[0]!.id).toBe('tomato')
    expect(searchIngredients(entries, 'tomato paste', 5, 'en-US').map((row) => row.id)).toEqual(['custom:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'])
  })
})

describe('structured units', () => {
  it('lists every unit code, including oz, lb, cup, package, can and bottle', () => {
    expect(PANTRY_UNIT_CODES).toEqual(['g', 'kg', 'oz', 'lb', 'ml', 'l', 'piece', 'tsp', 'tbsp', 'cup', 'package', 'can', 'bottle', 'clove', 'pinch', 'slice', 'sprig', 'toTaste'])
    for (const [typed, code] of [['ounces', 'oz'], ['ons', 'oz'], ['lbs', 'lb'], ['su bardağı', 'cup'], ['paket', 'package'], ['konserve', 'can'], ['şişe', 'bottle'], ['adet', 'piece']] as const) {
      expect(parsePantryUnit(typed).code, typed).toBe(code)
    }
  })

  it('converts only within a family, with exact definitions', () => {
    expect(convertPantryQuantity(1, 'lb', 'g')).toBe(453.592)
    expect(convertPantryQuantity(16, 'oz', 'lb')).toBe(1)
    expect(convertPantryQuantity(1, 'kg', 'oz')).toBe(35.274)
    expect(unitsCompatible('oz', 'kg')).toBe(true)
    expect(unitsCompatible('piece', 'g')).toBe(false)
    expect(unitsCompatible('cup', 'ml')).toBe(false)
    expect(unitsCompatible('can', 'g')).toBe(false)
  })
})

describe('notification copy', () => {
  it('chooses text by recipient locale and falls back to the default locale', () => {
    expect(notificationCopy('weekly_plan', 1, '', '', 'tr-TR').body).toBe('Haftalık plan hazır')
    expect(notificationCopy('weekly_plan', 1, '', '', 'en-US')).toEqual(notificationCopy('weekly_plan', 1, '', '', 'tr-TR'))
    expect(notificationCopy('meal_veto', 1234, '', '', 'tr-TR').body).toBe('1.234 yemek için bu hafta olmaz')
    expect(notificationCopy('meal_veto', 2, 'm', '', 'de-DE').route).toBe('mealroutine://week')
  })
})

describe('regional settings API', () => {
  it('exposes, validates and stores account and household settings', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'regional-ada', { email: 'ada@example.de' })
    expect(ada.body.settings).toEqual(REGIONAL_DEFAULTS)

    const settings = await app.inject({ method: 'GET', url: '/v1/account/settings', headers: ada.auth })
    expect(settings.json()).toEqual({ settings: REGIONAL_DEFAULTS })
    for (const [payload, error] of [
      [{ locale: 'xx-YY' }, 'unsupported_locale'],
      [{ currencyCode: 'TL' }, 'invalid_currency'],
      [{ measurementSystem: 'royal' }, 'invalid_measurement_system'],
      [{ timezone: 'GMT+3' }, 'invalid_timezone'],
      [{ countryCode: 'TUR' }, 'invalid_country'],
    ] as const) {
      const rejected = await app.inject({ method: 'PATCH', url: '/v1/account/settings', headers: ada.auth, payload })
      expect(rejected.statusCode).toBe(400)
      expect(rejected.json().error).toBe(error)
    }
    const unknownField = await app.inject({ method: 'PATCH', url: '/v1/account/settings', headers: ada.auth, payload: { currency: 'USD' } })
    expect(unknownField.json().error).toBe('invalid_request')

    const patched = await app.inject({ method: 'PATCH', url: '/v1/account/settings', headers: ada.auth, payload: { timezone: 'America/Los_Angeles' } })
    expect(patched.json().settings).toEqual({ ...REGIONAL_DEFAULTS, timezone: 'America/Los_Angeles' })
    const me = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: ada.auth })
    expect(me.json().settings.timezone).toBe('America/Los_Angeles')

    const invalidHousehold = await app.inject({ method: 'POST', url: '/v1/households', headers: ada.auth, payload: { name: 'Ev', timezone: 'Europe/Nowhere' } })
    expect(invalidHousehold.json()).toMatchObject({ error: 'invalid_timezone', field: 'timezone' })
    const created = await app.inject({ method: 'POST', url: '/v1/households', headers: ada.auth, payload: { name: 'Ev', currencyCode: 'EUR' } })
    const householdId = created.json().household.id as string
    expect(created.json().household.settings).toEqual({ countryCode: 'TR', currencyCode: 'EUR', measurementSystem: 'metric', timezone: 'America/Los_Angeles' })

    const bea = await signIn(app, 'regional-bea')
    const invite = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/invites`, headers: ada.auth })
    const code = invite.json().household.invites[0].code as string
    const joined = await app.inject({ method: 'POST', url: `/v1/invites/${code}/accept`, headers: bea.auth })
    expect(joined.json().household.settings.timezone).toBe('America/Los_Angeles')
    const memberPatch = await app.inject({ method: 'PATCH', url: `/v1/households/${householdId}/settings`, headers: bea.auth, payload: { timezone: 'UTC' } })
    expect(memberPatch.statusCode).toBe(403)

    const ownerPatch = await app.inject({ method: 'PATCH', url: `/v1/households/${householdId}/settings`, headers: ada.auth, payload: { measurementSystem: 'imperial', timezone: 'Pacific/Auckland' } })
    expect(ownerPatch.json().household.settings).toEqual({ countryCode: 'TR', currencyCode: 'EUR', measurementSystem: 'imperial', timezone: 'Pacific/Auckland' })
    const account = await app.inject({ method: 'GET', url: '/v1/account/settings', headers: ada.auth })
    expect(account.json().settings.measurementSystem).toBe('metric')

    const sunday = await app.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/mutations`,
      headers: { ...ada.auth, 'idempotency-key': 'regional-sunday' },
      payload: {
        entityType: 'plan',
        entityId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
        operationType: 'upsert',
        baseRevision: 0,
        payload: { weekStart: '2030-06-02', status: 'draft', isFinalized: false, meals: [] },
      },
    })
    expect(sunday.statusCode).toBe(400)
    expect(sunday.json()).toMatchObject({ error: 'invalid_week_start', field: 'weekStart' })
    await app.close()
  })

  it('serves the dictionary in the requested locale shape and registers custom ingredients in a locale', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'regional-dictionary')
    const listed = await app.inject({ method: 'GET', url: '/v1/ingredients?q=domates&limit=3', headers: ada.auth })
    expect(listed.json()).toMatchObject({ version: 2, locale: 'tr-TR', sourceLocale: 'tr-TR' })
    expect(listed.json().ingredients[0]).toMatchObject({ id: 'tomato', names: { 'tr-TR': 'Domates' }, scope: 'dictionary' })
    const unsupported = await app.inject({ method: 'GET', url: '/v1/ingredients?locale=xx-YY', headers: ada.auth })
    expect(unsupported.json().error).toBe('unsupported_locale')

    const householdId = (await app.inject({ method: 'POST', url: '/v1/households', headers: ada.auth, payload: { name: 'Ev' } })).json().household.id as string
    const custom = 'custom:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    const registered = await app.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/ingredients`,
      headers: { ...ada.auth, 'idempotency-key': 'regional-custom' },
      payload: { id: custom, displayName: 'Ev salçası' },
    })
    expect(registered.json()).toEqual({
      id: custom,
      names: { 'tr-TR': 'Ev salçası' },
      aliases: {},
      sourceIds: [],
      displayName: 'Ev salçası',
      synonyms: [],
      scope: 'household',
    })
    await app.close()
  })
})
