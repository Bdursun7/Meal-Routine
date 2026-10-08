import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'
import type { FastifyInstance } from 'fastify'

const planId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const mealId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const groceryId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'

function session() {
  const app = buildApp({
    repo: memoryRepo(),
    config: testConfig(),
    verifier: testVerifier(),
  })
  return { app }
}

async function signIn(app: FastifyInstance, subject: string, givenName: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken: identityToken({ subject, givenName, familyName: '' }),
      givenName,
    },
  })
  expect(response.statusCode).toBe(200)
  const body = response.json()
  return {
    accountId: body.account.id as string,
    auth: { authorization: `Bearer ${body.accessToken}` },
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
  return response.json().household.id as string
}

function mutate(
  app: FastifyInstance,
  householdId: string,
  auth: { authorization: string },
  key: string,
  payload: { entityType: string; entityId: string; operationType: string; baseRevision: number; payload: Record<string, unknown> },
) {
  return app.inject({
    method: 'POST',
    url: `/v1/households/${householdId}/mutations`,
    headers: { ...auth, 'idempotency-key': key },
    payload,
  })
}

describe('shared board sync', () => {
  it('replays an idempotent grocery add without doubling quantity', async () => {
    const { app } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const householdId = await createHousehold(app, ada.auth)
    const body = {
      entityType: 'grocery',
      entityId: groceryId,
      operationType: 'add',
      baseRevision: 0,
      payload: { itemKey: 'sut|l', quantity: 2 },
    }
    const first = await mutate(app, householdId, ada.auth, 'key-grocery-1', body)
    expect(first.statusCode).toBe(200)
    expect(first.json().entity.quantity).toBe(2)
    expect(first.json().revision).toBe(1)

    const replay = await mutate(app, householdId, ada.auth, 'key-grocery-1', body)
    expect(replay.statusCode).toBe(200)
    expect(replay.json()).toEqual(first.json())

    const board = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/board`,
      headers: ada.auth,
    })
    expect(board.statusCode).toBe(200)
    expect(board.json().grocery).toEqual([
      expect.objectContaining({ itemKey: 'sut|l', quantity: 2, revision: 1 }),
    ])

    const again = await mutate(app, householdId, ada.auth, 'key-grocery-2', {
      ...body,
      baseRevision: 1,
    })
    expect(again.statusCode).toBe(200)
    expect(again.json().entity.quantity).toBe(4)

    const stale = await mutate(app, householdId, ada.auth, 'key-grocery-3', body)
    expect(stale.statusCode).toBe(409)
    expect(stale.json().error).toBe('version_conflict')
    expect(stale.json().server.quantity).toBe(4)

    const still = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/board`,
      headers: ada.auth,
    })
    expect(still.json().grocery[0].quantity).toBe(4)
    await app.close()
  })

  it('returns a delta since the cursor and keeps meal, reaction, plan, and preference versions', async () => {
    const { app } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const householdId = await createHousehold(app, ada.auth)
    const plan = await mutate(app, householdId, ada.auth, 'key-plan', {
      entityType: 'plan',
      entityId: planId,
      operationType: 'upsert',
      baseRevision: 0,
      payload: {
        weekStart: '2030-06-03',
        status: 'draft',
        isFinalized: false,
        meals: [{ id: mealId, dayOffset: 0, recipeSlug: 'corba', title: 'Çorba' }],
      },
    })
    expect(plan.statusCode).toBe(200)
    expect(plan.json().entity.meals[0].title).toBe('Çorba')

    const veto = await mutate(app, householdId, ada.auth, 'key-veto', {
      entityType: 'reaction',
      entityId: mealId,
      operationType: 'set',
      baseRevision: 0,
      payload: { reaction: 'veto', mealRevision: 1 },
    })
    expect(veto.statusCode).toBe(200)
    expect(veto.json().entity.status).toBe('vetoed')
    expect(veto.json().entity.reactions[0].reaction).toBe('veto')

    const replaced = await mutate(app, householdId, ada.auth, 'key-replace', {
      entityType: 'meal',
      entityId: mealId,
      operationType: 'replace',
      baseRevision: veto.json().entity.revision,
      payload: { recipeSlug: 'pilav', title: 'Pilav' },
    })
    expect(replaced.statusCode).toBe(200)
    expect(replaced.json().entity.status).toBe('replaced')
    expect(replaced.json().entity.title).toBe('Pilav')

    const staleMeal = await mutate(app, householdId, ada.auth, 'key-stale-meal', {
      entityType: 'meal',
      entityId: mealId,
      operationType: 'replace',
      baseRevision: 1,
      payload: { recipeSlug: 'eski', title: 'Eski' },
    })
    expect(staleMeal.statusCode).toBe(409)
    expect(staleMeal.json().error).toBe('version_conflict')
    expect(staleMeal.json().entityType).toBe('meal')
    expect(staleMeal.json().server.title).toBe('Pilav')

    const preference = await mutate(app, householdId, ada.auth, 'key-pref', {
      entityType: 'preference',
      entityId: householdId,
      operationType: 'update',
      baseRevision: 1,
      payload: { maxWeekdayMinutes: 45, cookingDays: [0, 2] },
    })
    expect(preference.statusCode).toBe(200)
    expect(preference.json().entity.maxWeekdayMinutes).toBe(45)
    expect(preference.json().revision).toBe(2)

    const delta = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/changes?cursor=${plan.json().cursor}`,
      headers: ada.auth,
    })
    expect(delta.statusCode).toBe(200)
    const cursors = delta.json().changes.map((change: { cursor: number }) => change.cursor)
    expect(cursors.every((cursor: number) => cursor > plan.json().cursor)).toBe(true)
    expect(delta.json().changes.some((change: { entityType: string }) => change.entityType === 'meal')).toBe(true)
    expect(delta.json().cursor).toBeGreaterThan(plan.json().cursor)

    const board = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/board`,
      headers: ada.auth,
    })
    expect(board.json().activity.length).toBeGreaterThan(0)
    expect(board.json().plans[0].meals[0].title).toBe('Pilav')
    expect(board.json().preference.revision).toBe(2)
    await app.close()
  })

  it('refuses another household and an unknown id', async () => {
    const { app } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const bea = await signIn(app, 'bea', 'Bea')
    const householdId = await createHousehold(app, ada.auth)
    await createHousehold(app, bea.auth)

    const board = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/board`,
      headers: bea.auth,
    })
    expect(board.statusCode).toBe(403)
    expect(board.json().error).toBe('forbidden')

    const changes = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}/changes`,
      headers: bea.auth,
    })
    expect(changes.statusCode).toBe(403)

    const write = await mutate(app, householdId, bea.auth, 'key-cross', {
      entityType: 'grocery',
      entityId: groceryId,
      operationType: 'add',
      baseRevision: 0,
      payload: { itemKey: 'sut|l', quantity: 1 },
    })
    expect(write.statusCode).toBe(403)

    const missing = await app.inject({
      method: 'GET',
      url: '/v1/households/dddddddd-dddd-4ddd-8ddd-dddddddddddd/board',
      headers: ada.auth,
    })
    expect(missing.statusCode).toBe(404)
    expect(missing.json().error).toBe('not_found')

    const missingKey = await app.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/mutations`,
      headers: ada.auth,
      payload: {
        entityType: 'grocery',
        entityId: groceryId,
        operationType: 'add',
        baseRevision: 0,
        payload: { itemKey: 'sut|l', quantity: 1 },
      },
    })
    expect(missingKey.statusCode).toBe(400)
    await app.close()
  })
})
