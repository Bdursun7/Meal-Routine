import { randomBytes } from 'node:crypto'
import { copyFile, mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import type { FastifyInstance } from 'fastify'
import { Pool } from 'pg'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { seedIngredients } from '../src/ingredients.js'
import { listMigrationFiles, migrate, migrationsDirectory } from '../src/migrate.js'
import { createPgRepository } from '../src/pgRepository.js'
import { testConfig, testVerifier } from './helpers.js'

const databaseUrl = process.env.DATABASE_URL

describe.skipIf(!databaseUrl)('postgres pantry', () => {
  const schema = `mr_pantry_${randomBytes(4).toString('hex')}`
  let admin: Pool
  let pool: Pool
  let app: FastifyInstance
  let legacyDir = ''

  beforeAll(async () => {
    admin = new Pool({ connectionString: databaseUrl })
    await admin.query(`CREATE SCHEMA ${schema}`)
    pool = new Pool({ connectionString: databaseUrl, options: `-c search_path=${schema}` })
    legacyDir = await mkdtemp(path.join(tmpdir(), 'mr-v41-'))
    const files = await listMigrationFiles(migrationsDirectory())
    for (const file of files.filter((name) => name < '0012')) {
      await copyFile(path.join(migrationsDirectory(), file), path.join(legacyDir, file))
    }
    await migrate(pool, legacyDir)
    app = buildApp({ repo: createPgRepository(pool), config: testConfig({ rateLimitMax: 1000 }), verifier: testVerifier() })
  })

  afterAll(async () => {
    await app?.close()
    await pool?.end()
    if (legacyDir) await rm(legacyDir, { recursive: true, force: true })
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`)
      await admin.end()
    }
  })

  it('upgrades a V4.1 database through 0012 and 0013 without losing data and with deterministic defaults', async () => {
    const accountId = '11111111-1111-4111-8111-111111111111'
    const householdId = '22222222-2222-4222-8222-222222222222'
    const sundayPlan = '33333333-3333-4333-8333-333333333333'
    const mondayPlan = '44444444-4444-4444-8444-444444444444'
    const otherSunday = '55555555-5555-4555-8555-555555555556'
    await pool.query(`INSERT INTO accounts (id, display_name, given_name) VALUES ($1, 'Ada', 'Ada')`, [accountId])
    await pool.query(
      `INSERT INTO auth_identities (id, account_id, provider, subject) VALUES ('66666666-6666-4666-8666-666666666666', $1, 'dev', 'pg-legacy-ada')`,
      [accountId],
    )
    await pool.query(`INSERT INTO households (id, name, owner_account_id) VALUES ($1, 'Ev', $2)`, [householdId, accountId])
    await pool.query(`INSERT INTO household_members (id, household_id, account_id, role, display_name) VALUES ('77777777-7777-4777-8777-777777777777', $1, $2, 'owner', 'Ada')`, [householdId, accountId])
    await pool.query(`INSERT INTO household_preferences (household_id) VALUES ($1)`, [householdId])
    // V5.0 sent Istanbul's Monday 2030-06-03 00:00 through a UTC formatter, which stored Sunday 2030-06-02.
    await pool.query(`INSERT INTO shared_plans (id, household_id, week_start, status) VALUES ($1, $2, '2030-06-02', 'draft')`, [sundayPlan, householdId])
    // A Sunday whose Monday is already taken stays put rather than colliding.
    await pool.query(`INSERT INTO shared_plans (id, household_id, week_start, status) VALUES ($1, $2, '2030-06-10', 'draft')`, [mondayPlan, householdId])
    await pool.query(`INSERT INTO shared_plans (id, household_id, week_start, status) VALUES ($1, $2, '2030-06-09', 'draft')`, [otherSunday, householdId])
    await pool.query(
      `INSERT INTO shared_meals (id, plan_id, day_offset, recipe_slug, title, status) VALUES ('88888888-8888-4888-8888-888888888888', $1, 0, 'menemen', 'Menemen', 'cooked')`,
      [sundayPlan],
    )
    await pool.query(
      `INSERT INTO household_activity (id, household_id, actor_account_id, actor_name, kind, meal_title, detail)
       VALUES ('99999999-9999-4999-8999-999999999990', $1, $2, 'Ada', 'mealCooked', 'Menemen', 'Pişti'),
              ('99999999-9999-4999-8999-99999999999a', $1, $2, 'Ada', 'note', 'Menemen', 'Serbest metin')`,
      [householdId, accountId],
    )
    const before = await counts()

    const v5Dir = await mkdtemp(path.join(tmpdir(), 'mr-v50-'))
    for (const file of await listMigrationFiles(migrationsDirectory())) {
      if (file < '0013') await copyFile(path.join(migrationsDirectory(), file), path.join(v5Dir, file))
    }
    expect(await migrate(pool, v5Dir)).toEqual(['0012_pantry'])
    await rm(v5Dir, { recursive: true, force: true })
    const custom = 'custom:12121212-1212-4121-8121-121212121212'
    await pool.query(`INSERT INTO ingredients (id, household_id, display_name, synonyms) VALUES ($1, $2, 'Ev salçası', ARRAY['salca', 'biber salçası'])`, [custom, householdId])
    await pool.query(
      `INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location) VALUES ('abababab-abab-4bab-8bab-abababababab', $1, 'tomato', 'Domates', 400, 'g', 'refrigerator')`,
      [householdId],
    )

    expect(await migrate(pool)).toEqual(['0013_globalization'])
    expect(await counts()).toEqual(before)
    expect(await migrate(pool)).toEqual([])

    const account = await pool.query('SELECT locale, country_code, currency_code, measurement_system, timezone FROM accounts WHERE id = $1', [accountId])
    expect(account.rows[0]).toEqual({ locale: 'tr-TR', country_code: 'TR', currency_code: 'TRY', measurement_system: 'metric', timezone: 'Europe/Istanbul' })
    const household = await pool.query('SELECT country_code, currency_code, measurement_system, timezone, revision FROM households WHERE id = $1', [householdId])
    expect(household.rows[0]).toEqual({ country_code: 'TR', currency_code: 'TRY', measurement_system: 'metric', timezone: 'Europe/Istanbul', revision: 1 })
    const defaults = await pool.query<{ column_name: string; column_default: string | null }>(
      `SELECT column_name, column_default FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name IN ('accounts', 'households')
          AND column_name IN ('locale', 'country_code', 'currency_code', 'measurement_system', 'timezone')`,
    )
    expect(defaults.rows).toHaveLength(9)
    expect(defaults.rows.every((row) => row.column_default === null)).toBe(true)

    const plans = await pool.query<{ id: string; week_start: string; revision: number }>(
      `SELECT id, to_char(week_start, 'YYYY-MM-DD') AS week_start, revision FROM shared_plans WHERE household_id = $1 ORDER BY id`,
      [householdId],
    )
    expect(plans.rows).toEqual([
      { id: sundayPlan, week_start: '2030-06-03', revision: 1 },
      { id: mondayPlan, week_start: '2030-06-10', revision: 1 },
      { id: otherSunday, week_start: '2030-06-09', revision: 1 },
    ])
    const activity = await pool.query<{ detail: string; detail_code: string | null }>(
      'SELECT detail, detail_code FROM household_activity WHERE household_id = $1 ORDER BY id',
      [householdId],
    )
    expect(activity.rows).toEqual([{ detail: 'Pişti', detail_code: 'cooked' }, { detail: 'Serbest metin', detail_code: null }])

    const names = await pool.query<{ count: string }>(`SELECT count(*) FROM ingredient_names WHERE locale = 'tr-TR'`)
    expect(Number(names.rows[0]!.count)).toBe(seedIngredients().length + 1)
    const customAliases = await pool.query('SELECT alias, position FROM ingredient_aliases WHERE ingredient_id = $1 ORDER BY position', [custom])
    expect(customAliases.rows).toEqual([{ alias: 'salca', position: 1 }, { alias: 'biber salçası', position: 2 }])
    const pantryRow = await pool.query('SELECT quantity::float AS quantity, unit, unit_bucket FROM pantry_items WHERE household_id = $1', [householdId])
    expect(pantryRow.rows).toEqual([{ quantity: 400, unit: 'g', unit_bucket: 'mass' }])

    const ada = await devSignIn(app, 'pg-legacy-ada', 'Ada')
    const me = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: ada.auth })
    expect(me.json().settings).toEqual({ locale: 'tr-TR', countryCode: 'TR', currencyCode: 'TRY', measurementSystem: 'metric', timezone: 'Europe/Istanbul' })
    const board = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/board`, headers: ada.auth })
    expect(board.statusCode).toBe(200)
    const plan = board.json().plans.find((row: { id: string }) => row.id === sundayPlan)
    expect(plan).toMatchObject({ weekStart: '2030-06-03' })
    expect(JSON.stringify(board.json())).toContain('menemen')
    expect(board.json().activity.find((row: { mealTitle: string; detailCode: string | null }) => row.detailCode === 'cooked')).toMatchObject({ mealTitle: 'Menemen' })
    const listed = await app.inject({ method: 'GET', url: `/v1/ingredients?householdId=${householdId}&q=salca`, headers: ada.auth })
    expect(listed.json().ingredients.find((row: { id: string }) => row.id === custom)).toMatchObject({
      names: { 'tr-TR': 'Ev salçası' },
      aliases: { 'tr-TR': ['salca', 'biber salçası'] },
      scope: 'household',
    })
    const seeded = await pool.query<{ count: string }>('SELECT count(*) FROM ingredients WHERE household_id IS NULL')
    expect(Number(seeded.rows[0]!.count)).toBe(seedIngredients().length)
  })

  it('stores regional settings, locale-keyed custom ingredients and new units', async () => {
    const bea = await devSignIn(app, 'pg-regional-bea', 'Bea')
    const created = await app.inject({
      method: 'POST', url: '/v1/households', headers: bea.auth,
      payload: { name: 'Home', countryCode: 'US', currencyCode: 'USD', measurementSystem: 'imperial', timezone: 'America/Los_Angeles' },
    })
    expect(created.statusCode).toBe(200)
    const householdId = created.json().household.id as string
    expect(created.json().household.settings).toEqual({ countryCode: 'US', currencyCode: 'USD', measurementSystem: 'imperial', timezone: 'America/Los_Angeles' })
    const stored = await pool.query('SELECT country_code, currency_code, measurement_system, timezone FROM households WHERE id = $1', [householdId])
    expect(stored.rows[0]).toEqual({ country_code: 'US', currency_code: 'USD', measurement_system: 'imperial', timezone: 'America/Los_Angeles' })

    const patched = await app.inject({ method: 'PATCH', url: '/v1/account/settings', headers: bea.auth, payload: { locale: 'en-US', timezone: 'Pacific/Auckland' } })
    expect(patched.json().settings).toEqual({ locale: 'en-US', countryCode: 'TR', currencyCode: 'TRY', measurementSystem: 'metric', timezone: 'Pacific/Auckland' })
    const bad = await app.inject({ method: 'PATCH', url: `/v1/households/${householdId}/settings`, headers: bea.auth, payload: { currencyCode: 'TL' } })
    expect(bad.statusCode).toBe(400)
    expect(bad.json()).toMatchObject({ error: 'invalid_currency', field: 'currencyCode' })
    await expect(pool.query(`UPDATE households SET currency_code = 'tl' WHERE id = $1`, [householdId])).rejects.toMatchObject({ code: '23514' })

    const custom = 'custom:34343434-3434-4343-8343-343434343434'
    const registered = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...bea.auth, 'idempotency-key': 'pg-regional-ingredient' },
      payload: { id: custom, displayName: 'Hot sauce' },
    })
    expect(registered.json()).toMatchObject({ id: custom, names: { 'en-US': 'Hot sauce' }, displayName: 'Hot sauce', scope: 'household' })
    const names = await pool.query('SELECT locale, display_name FROM ingredient_names WHERE ingredient_id = $1', [custom])
    expect(names.rows).toEqual([{ locale: 'en-US', display_name: 'Hot sauce' }])

    const post = (key: string, payload: Record<string, unknown>) =>
      app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...bea.auth, 'idempotency-key': key }, payload })
    expect((await post('pg-regional-lb', { ingredientId: 'rice', displayName: 'Rice', quantity: 1, unit: 'lb', location: 'pantry' })).json()).toMatchObject({ unit: 'lb', quantity: 1 })
    const merged = await post('pg-regional-oz', { ingredientId: 'rice', displayName: 'Rice', quantity: 8, unit: 'oz', location: 'pantry' })
    expect(merged.json()).toMatchObject({ unit: 'lb', quantity: 1.5, version: 2 })
    expect((await post('pg-regional-can', { ingredientId: 'tomato', displayName: 'Tomato', quantity: 2, unit: 'can', location: 'pantry' })).json()).toMatchObject({ unit: 'can', quantity: 2 })
  })

  it('enforces the pantry rules in the database and through the API', async () => {
    const ada = await devSignIn(app, 'pg-pantry-owner', 'Ada')
    const householdId = (await app.inject({ method: 'POST', url: '/v1/households', headers: ada.auth, payload: { name: 'Kiler' } })).json().household.id as string
    const post = (key: string, payload: Record<string, unknown>) =>
      app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...ada.auth, 'idempotency-key': key }, payload })

    const grams = await post('pg-pantry-g', { ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g', location: 'refrigerator', dateType: 'useBy', dateValue: '2030-01-05' })
    expect(grams.statusCode).toBe(200)
    expect(grams.json()).toMatchObject({ ingredientId: 'tomato', dateType: 'useBy', dateValue: '2030-01-05', version: 1 })
    const kilos = await post('pg-pantry-kg', { ingredientId: 'tomatoes', displayName: 'Domates', quantity: 1, unit: 'kg', location: 'refrigerator' })
    expect(kilos.json()).toMatchObject({ id: grams.json().id, quantity: 1400, version: 2, dateType: 'useBy' })
    expect((await post('pg-pantry-replay', { ingredientId: 'tomato', displayName: 'Domates', quantity: 1, unit: 'kg', location: 'refrigerator' })).json().quantity).toBe(2400)
    expect((await post('pg-pantry-replay', { ingredientId: 'tomato', displayName: 'Domates', quantity: 1, unit: 'kg', location: 'refrigerator' })).json().quantity).toBe(2400)
    expect((await post('pg-pantry-piece', { ingredientId: 'tomato', displayName: 'Domates', quantity: 3, unit: 'piece', location: 'pantry' })).statusCode).toBe(409)
    expect((await post('pg-pantry-piece-ok', { ingredientId: 'tomato', displayName: 'Domates', quantity: 3, unit: 'piece', location: 'pantry', confirmSeparate: true })).statusCode).toBe(200)
    expect((await post('pg-pantry-cherry', { ingredientId: 'cherry-tomato', displayName: 'Domates', quantity: 200, unit: 'g', location: 'refrigerator' })).statusCode).toBe(200)
    expect((await post('pg-pantry-free', { ingredientId: 'domates', displayName: 'Domates', quantity: 1, unit: 'g', location: 'pantry' })).json().error).toBe('unknown_ingredient')

    const stale = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${grams.json().id}?baseVersion=1`,
      headers: { ...ada.auth, 'idempotency-key': 'pg-pantry-stale' }, payload: { quantity: 5 },
    })
    expect(stale.statusCode).toBe(409)
    expect(stale.json().current).toMatchObject({ quantity: 2400, version: 3 })

    const consume = { operation: 'consume', lines: [{ ingredientId: 'tomato', quantity: 1, unit: 'kg' }, { ingredientId: 'cherry-tomato', quantity: 50, unit: 'g' }] }
    const reconcile = () => app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...ada.auth, 'idempotency-key': 'pg-pantry-consume' }, payload: consume })
    const first = await reconcile()
    const replay = await reconcile()
    expect(first.statusCode).toBe(200)
    expect(replay.json()).toEqual(first.json())
    const items = (await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: ada.auth })).json().items as { ingredientId: string; unit: string; quantity: number }[]
    expect(items.find((row) => row.ingredientId === 'tomato' && row.unit === 'g')?.quantity).toBe(1400)
    expect(items.find((row) => row.ingredientId === 'cherry-tomato')?.quantity).toBe(150)
    expect(items).toHaveLength(3)

    await expect(pool.query(
      `INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location) VALUES ($1, $2, 'domates', 'Domates', 1, 'g', 'pantry')`,
      ['99999999-9999-4999-8999-999999999991', householdId],
    )).rejects.toMatchObject({ code: '23503' })
    await expect(pool.query(
      `INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location) VALUES ($1, $2, 'tomato', 'Domates', 1, 'kg', 'pantry')`,
      ['99999999-9999-4999-8999-999999999992', householdId],
    )).rejects.toMatchObject({ code: '23505' })
    await expect(pool.query(
      `INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location, date_type) VALUES ($1, $2, 'rice', 'Pirinç', 1, 'kg', 'pantry', 'useBy')`,
      ['99999999-9999-4999-8999-999999999993', householdId],
    )).rejects.toMatchObject({ code: '23514' })
    await expect(pool.query(
      `INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location) VALUES ($1, $2, 'rice', 'Pirinç', 1, 'kova', 'pantry')`,
      ['99999999-9999-4999-8999-999999999994', householdId],
    )).rejects.toMatchObject({ code: '23514' })
    await expect(pool.query(`INSERT INTO ingredients (id, display_name) VALUES ('custom:not-a-uuid', 'X')`)).rejects.toMatchObject({ code: '23514' })

    const custom = 'custom:55555555-5555-4555-8555-555555555555'
    const registered = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...ada.auth, 'idempotency-key': 'pg-pantry-ingredient' }, payload: { id: custom, displayName: 'Ev salçası' } })
    expect(registered.statusCode).toBe(200)
    expect((await post('pg-pantry-custom', { ingredientId: custom, displayName: 'Ev salçası', quantity: 2, unit: 'piece', location: 'pantry' })).statusCode).toBe(200)
    const listed = await app.inject({ method: 'GET', url: `/v1/ingredients?householdId=${householdId}&q=salca`, headers: ada.auth })
    expect(listed.json().ingredients.map((row: { id: string }) => row.id)).toContain(custom)

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ada.auth })
    expect(removed.json()).toEqual({ deleted: true, household: 'deleted' })
    for (const table of ['pantry_items', 'ingredients', 'pantry_idempotency']) {
      const left = await pool.query<{ count: string }>(`SELECT count(*) FROM ${table} WHERE household_id = $1`, [householdId])
      expect(Number(left.rows[0]!.count), table).toBe(0)
    }
  })

  async function counts(): Promise<Record<string, number>> {
    const out: Record<string, number> = {}
    for (const table of ['accounts', 'households', 'household_members', 'shared_plans', 'shared_meals', 'sessions']) {
      const result = await pool.query<{ count: string }>(`SELECT count(*) FROM ${table}`)
      out[table] = Number(result.rows[0]!.count)
    }
    return out
  }
})

async function devSignIn(app: FastifyInstance, subject: string, displayName: string) {
  const response = await app.inject({ method: 'POST', url: '/v1/auth/dev', payload: { subject, displayName } })
  expect(response.statusCode).toBe(200)
  return { auth: { authorization: `Bearer ${response.json().accessToken}` } }
}
