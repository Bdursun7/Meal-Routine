import { randomBytes } from 'node:crypto'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { Pool } from 'pg'
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
})
