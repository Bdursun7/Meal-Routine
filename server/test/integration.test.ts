import { randomBytes } from 'node:crypto'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { Pool } from 'pg'
import type { FastifyInstance } from 'fastify'
import { buildApp } from '../src/app.js'
import { migrate } from '../src/migrate.js'
import { createPgRepository } from '../src/pgRepository.js'
import { identityToken, testConfig, testVerifier } from './helpers.js'

const databaseUrl = process.env.DATABASE_URL

describe.skipIf(!databaseUrl)('postgres integration', () => {
  const schema = `mr_it_${randomBytes(4).toString('hex')}`
  let admin: Pool
  let pool: Pool

  beforeAll(async () => {
    admin = new Pool({ connectionString: databaseUrl })
    await admin.query(`CREATE SCHEMA ${schema}`)
    pool = new Pool({
      connectionString: databaseUrl,
      options: `-c search_path=${schema}`,
    })
    await migrate(pool)
  })

  afterAll(async () => {
    await pool?.end()
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`)
      await admin.end()
    }
  })

  it('signs in, refuses a duplicate Google account, and hides another household', async () => {
    const repo = createPgRepository(pool)
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const apple = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: {
        identityToken: identityToken({
          subject: 'pg-apple',
          email: 'pg@example.com',
          emailVerified: true,
          givenName: 'Ada',
        }),
        givenName: 'Ada',
      },
    })
    expect(apple.statusCode).toBe(200)
    const google = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: {
        identityToken: identityToken({
          subject: 'pg-google',
          email: 'pg@example.com',
          emailVerified: true,
        }),
      },
    })
    expect(google.statusCode).toBe(409)
    expect(google.json().error).toBe('link_required')

    const ownerId = apple.json().account.id as string
    const householdId = '22222222-2222-4222-8222-222222222222'
    await pool.query(
      `INSERT INTO households (id, name, owner_account_id) VALUES ($1, 'Ev', $2)`,
      [householdId, ownerId],
    )
    await pool.query(
      `INSERT INTO household_members (id, household_id, account_id, role, display_name)
       VALUES ($1, $2, $3, 'owner', 'Ada')`,
      ['33333333-3333-4333-8333-333333333333', householdId, ownerId],
    )
    const stranger = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: {
        identityToken: identityToken({ subject: 'pg-stranger', givenName: 'Bea' }),
        givenName: 'Bea',
      },
    })
    const denied = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}`,
      headers: { authorization: `Bearer ${stranger.json().accessToken}` },
    })
    expect([403, 404]).toContain(denied.statusCode)
    const allowed = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}`,
      headers: { authorization: `Bearer ${apple.json().accessToken}` },
    })
    expect(allowed.statusCode).toBe(200)

    await pool.query(
      `INSERT INTO household_members (id, household_id, account_id, role, display_name)
       VALUES ($1, $2, $3, 'member', 'Bea')`,
      ['44444444-4444-4444-8444-444444444444', householdId, stranger.json().account.id],
    )
    const third = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: {
        identityToken: identityToken({ subject: 'pg-third', givenName: 'Cem' }),
        givenName: 'Cem',
      },
    })
    await expect(
      pool.query(
        `INSERT INTO household_members (id, household_id, account_id, role, display_name)
         VALUES ($1, $2, $3, 'member', 'Cem')`,
        ['55555555-5555-4555-8555-555555555555', householdId, third.json().account.id],
      ),
    ).rejects.toMatchObject({ code: '23514' })
    await app.close()
  })

  it('runs dev signup through household plan, veto, grocery, changes, and account delete', async () => {
    const app = buildApp({
      repo: createPgRepository(pool),
      config: testConfig(),
      verifier: testVerifier(),
      readiness: async () => {
        await pool.query('SELECT 1')
        return true
      },
    })
    const ready = await app.inject({ method: 'GET', url: '/ready' })
    expect(ready.statusCode).toBe(200)

    const ada = await devSignIn(app, 'qa-ada', 'Ada')
    const bea = await devSignIn(app, 'qa-bea', 'Bea')
    const created = await app.inject({
      method: 'POST',
      url: '/v1/households',
      headers: ada.auth,
      payload: { name: 'Ev' },
    })
    expect(created.statusCode).toBe(200)
    const householdId = created.json().household.id as string

    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/invites`,
      headers: ada.auth,
    })
    expect(invited.statusCode).toBe(200)
    const code = invited.json().household.invites[0].code as string
    const joined = await app.inject({
      method: 'POST',
      url: `/v1/invites/${code}/accept`,
      headers: bea.auth,
    })
    expect(joined.statusCode).toBe(200)
    expect(joined.json().household.role).toBe('member')

    const planId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    const mealId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    const groceryId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    const plan = await mutate(app, householdId, ada.auth, 'qa-plan-0001', {
      entityType: 'plan',
      entityId: planId,
      operationType: 'upsert',
      baseRevision: 0,
      payload: {
        weekStart: '2030-06-02',
        status: 'draft',
        isFinalized: false,
        meals: [{ id: mealId, dayOffset: 0, recipeSlug: 'corba', title: 'Çorba' }],
      },
    })
    expect(plan.statusCode).toBe(200)

    const veto = await mutate(app, householdId, bea.auth, 'qa-veto-0001', {
      entityType: 'reaction',
      entityId: mealId,
      operationType: 'set',
      baseRevision: 0,
      payload: { reaction: 'veto', mealRevision: 1 },
    })
    expect(veto.statusCode).toBe(200)
    expect(veto.json().entity.status).toBe('vetoed')

    const added = await mutate(app, householdId, ada.auth, 'qa-grocery-add', {
      entityType: 'grocery',
      entityId: groceryId,
      operationType: 'add',
      baseRevision: 0,
      payload: { itemKey: 'sut|l', quantity: 2 },
    })
    expect(added.statusCode).toBe(200)
    expect(added.json().revision).toBe(1)

    const checked = await mutate(app, householdId, bea.auth, 'qa-grocery-chk', {
      entityType: 'grocery',
      entityId: groceryId,
      operationType: 'check',
      baseRevision: 1,
      payload: { isChecked: true },
    })
    expect(checked.statusCode).toBe(200)
    expect(checked.json().entity.isChecked).toBe(true)

    const delta = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/changes?cursor=0`,
      headers: ada.auth,
    })
    expect(delta.statusCode).toBe(200)
    const types = delta.json().changes.map((change: { entityType: string }) => change.entityType)
    expect(types).toEqual(expect.arrayContaining(['plan', 'meal', 'grocery']))

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ada.auth })
    expect(removed.statusCode).toBe(200)
    expect(removed.json()).toEqual({ deleted: true, household: 'left' })

    const board = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/board`,
      headers: bea.auth,
    })
    expect(board.statusCode).toBe(200)
    expect(board.json().grocery).toEqual([
      expect.objectContaining({ itemKey: 'sut|l', isChecked: true }),
    ])

    const refresh = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: ada.refresh },
    })
    expect(refresh.statusCode).toBe(401)
    const exported = await app.inject({
      method: 'GET',
      url: '/v1/account/export',
      headers: ada.auth,
    })
    expect(exported.statusCode).toBe(401)

    const last = await app.inject({ method: 'DELETE', url: '/v1/account', headers: bea.auth })
    expect(last.statusCode).toBe(200)
    expect(last.json()).toEqual({ deleted: true, household: 'deleted' })
    const stored = await pool.query<{ deleted_at: Date | null }>(
      'SELECT deleted_at FROM households WHERE id = $1',
      [householdId],
    )
    expect(stored.rows[0]?.deleted_at).toBeTruthy()
    await app.close()
  })
})

async function devSignIn(app: FastifyInstance, subject: string, displayName: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/dev',
    payload: { subject, displayName },
  })
  expect(response.statusCode).toBe(200)
  const body = response.json()
  return {
    refresh: body.refreshToken as string,
    auth: { authorization: `Bearer ${body.accessToken}` },
  }
}

function mutate(
  app: FastifyInstance,
  householdId: string,
  auth: { authorization: string },
  key: string,
  payload: {
    entityType: string
    entityId: string
    operationType: string
    baseRevision: number
    payload: Record<string, unknown>
  },
) {
  return app.inject({
    method: 'POST',
    url: `/v1/households/${householdId}/mutations`,
    headers: { ...auth, 'idempotency-key': key },
    payload,
  })
}
