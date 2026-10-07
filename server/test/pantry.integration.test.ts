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

  it('applies 0012 on a V4.1 database without losing household, board or account data', async () => {
    const ada = await devSignIn(app, 'pg-pantry-ada', 'Ada')
    const household = await app.inject({ method: 'POST', url: '/v1/households', headers: ada.auth, payload: { name: 'Ev' } })
    const householdId = household.json().household.id as string
    const plan = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/mutations`, headers: { ...ada.auth, 'idempotency-key': 'pg-v41-plan' },
      payload: {
        entityType: 'plan', entityId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab', operationType: 'upsert', baseRevision: 0,
        payload: { weekStart: '2030-06-02', status: 'draft', isFinalized: false, meals: [{ id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbc', dayOffset: 0, recipeSlug: 'menemen', title: 'Menemen' }] },
      },
    })
    expect(plan.statusCode).toBe(200)
    const before = await counts()

    const applied = await migrate(pool)
    expect(applied).toEqual(['0012_pantry'])
    expect(await counts()).toEqual(before)
    const board = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/board`, headers: ada.auth })
    expect(board.statusCode).toBe(200)
    expect(JSON.stringify(board.json())).toContain('menemen')
    const seeded = await pool.query<{ count: string }>('SELECT count(*) FROM ingredients WHERE household_id IS NULL')
    expect(Number(seeded.rows[0]!.count)).toBe(seedIngredients().length)
    expect(await migrate(pool)).toEqual([])
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
