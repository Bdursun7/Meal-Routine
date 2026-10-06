import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { assertRuntimeConfig, loadConfig } from '../src/config.js'
import { createMemoryNotificationStore } from '../src/notifications.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'
import type { FastifyInstance } from 'fastify'

const historyId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
const recipeId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const lineId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'

describe('account privacy', () => {
  it('exports only the caller and deletes a solo household', async () => {
    const repo = memoryRepo()
    const notifications = createMemoryNotificationStore()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier(), notifications })
    const ada = await signIn(app, 'ada-solo')
    const again = await signIn(app, 'ada-solo')
    const uploaded = await app.inject({
      method: 'POST',
      url: '/v1/migration/upload',
      headers: ada.auth,
      payload: bundle('Gizli menemen'),
    })
    expect(uploaded.statusCode).toBe(200)
    await notifications.registerToken(ada.id, 'device-token-ada', 'ios')
    const household = await createHousehold(app, ada.auth)

    const exported = await app.inject({ method: 'GET', url: '/v1/account/export', headers: ada.auth })
    expect(exported.statusCode).toBe(200)
    const body = JSON.stringify(exported.json())
    expect(body).toContain('Gizli menemen')
    expect(body).toContain(ada.id)
    expect(body).not.toContain(ada.refresh)
    expect(body).not.toContain('device-token-ada')
    expect(exported.json().household.id).toBe(household.id)

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ada.auth })
    expect(removed.statusCode).toBe(200)
    expect(removed.json()).toEqual({ deleted: true, household: 'deleted' })
    expect(repo.deletionAudits()).toEqual([{ accountId: ada.id, householdOutcome: 'deleted' }])

    const stored = await repo.transaction(async (tx) => tx.household(household.id))
    expect(stored?.deletedAt).toBeTruthy()
    const tokens = await notifications.listTokens(ada.id)
    expect(tokens.every((row) => row.disabled)).toBe(true)
    expect(await notifications.activeTokens(ada.id)).toEqual([])

    const refresh = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: ada.refresh },
    })
    const second = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: again.refresh },
    })
    expect(refresh.statusCode).toBe(401)
    expect(second.statusCode).toBe(401)
    const againExport = await app.inject({ method: 'GET', url: '/v1/account/export', headers: ada.auth })
    expect(againExport.statusCode).toBe(401)
    const resigned = await signIn(app, 'ada-solo')
    expect(resigned.id).not.toBe(ada.id)
    await app.close()
  })

  it('keeps the household when a partner remains and hides the other person from export', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'ada-home')
    const bea = await signIn(app, 'bea-home')
    const household = await createHousehold(app, ada.auth)
    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const code = invited.json().household.invites[0].code as string
    const joined = await app.inject({
      method: 'POST',
      url: `/v1/invites/${code}/accept`,
      headers: bea.auth,
    })
    expect(joined.statusCode).toBe(200)
    const uploaded = await app.inject({
      method: 'POST',
      url: '/v1/migration/upload',
      headers: ada.auth,
      payload: bundle('Gizli menemen'),
    })
    expect(uploaded.statusCode).toBe(200)

    const beaExport = await app.inject({ method: 'GET', url: '/v1/account/export', headers: bea.auth })
    expect(beaExport.statusCode).toBe(200)
    expect(JSON.stringify(beaExport.json())).not.toContain('Gizli menemen')
    expect(beaExport.json().household).toEqual({ id: household.id, name: 'Ev', role: 'member' })

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ada.auth })
    expect(removed.json()).toEqual({ deleted: true, household: 'left' })
    const stored = await repo.transaction(async (tx) => tx.household(household.id))
    expect(stored?.deletedAt).toBeNull()
    expect(stored?.ownerAccountId).toBe(bea.id)
    const current = await app.inject({ method: 'GET', url: '/v1/households/current', headers: bea.auth })
    expect(current.statusCode).toBe(200)
    expect(current.json().household.role).toBe('owner')
    const adaExport = await app.inject({ method: 'GET', url: '/v1/account/export', headers: ada.auth })
    expect(adaExport.statusCode).toBe(401)
    await app.close()
  })

  it('refuses another household on read and write', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'ada-authz')
    const bea = await signIn(app, 'bea-authz')
    const household = await createHousehold(app, ada.auth)
    const routes = [
      { method: 'GET' as const, url: `/v1/households/${household.id}`, headers: {} },
      { method: 'GET' as const, url: `/v1/households/${household.id}/board`, headers: {} },
      { method: 'GET' as const, url: `/v1/households/${household.id}/changes`, headers: {} },
      {
        method: 'POST' as const,
        url: `/v1/households/${household.id}/mutations`,
        headers: { 'idempotency-key': 'privacy-authz-key' },
        payload: { entityType: 'meal', entityId: 'meal-authz', operationType: 'cook', baseRevision: 0, payload: {} },
      },
      { method: 'POST' as const, url: `/v1/households/${household.id}/invites`, headers: {} },
      { method: 'DELETE' as const, url: `/v1/households/${household.id}`, headers: {} },
      { method: 'PUT' as const, url: `/v1/households/${household.id}/board`, headers: {}, payload: { note: 'nope' } },
    ]
    for (const route of routes) {
      const response = await app.inject({
        method: route.method,
        url: route.url,
        headers: { ...bea.auth, ...route.headers },
        payload: 'payload' in route ? route.payload : undefined,
      })
      expect([403, 404]).toContain(response.statusCode)
      expect(response.body).not.toContain('ada-authz')
    }
    const own = await app.inject({
      method: 'GET',
      url: `/v1/households/${household.id}`,
      headers: ada.auth,
    })
    expect(own.statusCode).toBe(200)
    await app.close()
  })

  it('limits request size, rejects a wildcard origin, and only echoes the configured origin', async () => {
    expect(loadConfig({}).jwtSecret).toBe('')
    expect(loadConfig({}).databaseUrl).toBe('')
    expect(() => assertRuntimeConfig(loadConfig({}))).toThrow(/DATABASE_URL/)
    expect(() => assertRuntimeConfig(testConfig({
      databaseUrl: 'postgres://local/meal',
      jwtSecret: 'short',
    }))).toThrow(/JWT_SECRET/)
    expect(() => assertRuntimeConfig(testConfig({
      databaseUrl: 'postgres://local/meal',
      corsOrigin: '*',
    }))).toThrow(/CORS_ORIGIN/)

    const tiny = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: testVerifier(),
      bodyLimit: 64,
    })
    const oversized = await tiny.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: { identityToken: 'x'.repeat(200) },
    })
    expect(oversized.statusCode).toBe(413)
    expect(oversized.json()).toEqual({ error: 'invalid_request' })
    await tiny.close()

    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig({ corsOrigin: 'https://mealroutine.example' }),
      verifier: testVerifier(),
    })
    const allowed = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'https://mealroutine.example' },
    })
    expect(allowed.headers['access-control-allow-origin']).toBe('https://mealroutine.example')
    expect(allowed.headers['x-content-type-options']).toBe('nosniff')
    expect(allowed.headers['referrer-policy']).toBe('no-referrer')
    expect(allowed.headers['x-frame-options']).toBe('DENY')
    const denied = await app.inject({
      method: 'GET',
      url: '/health',
      headers: { origin: 'https://evil.example' },
    })
    expect(denied.headers['access-control-allow-origin']).toBeUndefined()
    const preflight = await app.inject({
      method: 'OPTIONS',
      url: '/v1/auth/apple',
      headers: { origin: 'https://mealroutine.example' },
    })
    expect(preflight.statusCode).toBe(204)
    expect(preflight.headers['access-control-allow-origin']).toBe('https://mealroutine.example')
    await app.close()

    const closed = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const plain = await closed.inject({ method: 'GET', url: '/health', headers: { origin: 'https://mealroutine.example' } })
    expect(plain.headers['access-control-allow-origin']).toBeUndefined()
    const ada = await signIn(closed, 'ada-limit')
    const household = await createHousehold(closed, ada.auth)
    const huge = await closed.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/mutations`,
      headers: { ...ada.auth, 'idempotency-key': 'privacy-limit-key' },
      payload: {
        entityType: 'meal',
        entityId: 'meal-1',
        operationType: 'cook',
        baseRevision: 0,
        payload: { note: 'n'.repeat(20_000) },
      },
    })
    expect(huge.statusCode).toBe(400)
    await closed.close()
  })
})

async function signIn(app: FastifyInstance, subject: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken: identityToken({ subject, givenName: subject, familyName: '' }),
      givenName: subject,
    },
  })
  expect(response.statusCode).toBe(200)
  const body = response.json()
  return {
    id: body.account.id as string,
    refresh: body.refreshToken as string,
    auth: { authorization: `Bearer ${body.accessToken as string}` },
  }
}

async function createHousehold(app: FastifyInstance, auth: { authorization: string }) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/households',
    headers: auth,
    payload: { name: 'Ev' },
  })
  expect(response.statusCode).toBe(200)
  return response.json().household as { id: string }
}

function bundle(nameTr: string) {
  const updatedAt = '2024-06-01T00:00:00Z'
  return {
    recipes: [{
      id: recipeId,
      slug: 'gizli',
      updatedAt,
      nameTr,
      nameEn: '',
      summaryTr: '',
      origin: 'manual',
      collectionState: 'readyToCook',
      sourceUrl: '',
      sourceKey: '',
      sourcePlatform: '',
      sourceTitle: '',
      userNotes: '',
      baseServings: 2,
      prepMinutes: 5,
      cookMinutes: 10,
      totalMinutes: 15,
      timeIsUnknown: false,
      servingsUnspecified: false,
      difficulty: 'easy',
      category: 'main',
      country: 'TR',
      diets: [],
      tags: [],
      photoUrl: '',
      ingredients: [{
        id: lineId,
        sortIndex: 0,
        ingredientId: 'egg',
        nameTr: 'Yumurta',
        nameEn: 'Egg',
        quantity: 2,
        unit: 'piece',
        noteTr: '',
        isOptional: false,
        includeInGrocery: true,
      }],
      steps: [],
    }],
    memories: [],
    favorites: [],
    history: [{
      id: historyId,
      recipeSlug: 'gizli',
      eventType: 'cooked',
      planWeekId: null,
      plannedMealId: null,
      replacementReason: '',
      createdAt: updatedAt,
    }],
    feedback: [],
  }
}
