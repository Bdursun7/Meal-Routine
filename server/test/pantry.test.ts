import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

async function setup() {
  const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
  const signIn = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: { identityToken: identityToken({ subject: 'pantry-owner', givenName: 'Ada' }), givenName: 'Ada' },
  })
  const auth = { authorization: `Bearer ${signIn.json().accessToken}` }
  const household = await app.inject({ method: 'POST', url: '/v1/households', headers: auth, payload: { name: 'Mutfak' } })
  return { app, auth, householdId: household.json().household.id as string }
}

describe('pantry', () => {
  it('creates, lists, updates and deletes a household pantry item', async () => {
    const { app, auth, householdId } = await setup()
    const created = await app.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/pantry/items`,
      headers: { ...auth, 'idempotency-key': 'pantry-create-1' },
      payload: {
        ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g', location: 'refrigerator',
      },
    })
    expect(created.statusCode).toBe(200)
    expect(created.json()).toMatchObject({ ingredientId: 'tomato', quantity: 400, revision: 1 })
    const itemId = created.json().id as string
    const listed = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })
    expect(listed.statusCode).toBe(200)
    expect(listed.json().items).toHaveLength(1)
    const updated = await app.inject({
      method: 'PATCH',
      url: `/v1/households/${householdId}/pantry/items/${itemId}?baseRevision=1`,
      headers: { ...auth, 'idempotency-key': 'pantry-update-1' },
      payload: { quantity: 250, minimumQuantity: 100 },
    })
    expect(updated.statusCode).toBe(200)
    expect(updated.json()).toMatchObject({ quantity: 250, minimumQuantity: 100, revision: 2 })
    const removed = await app.inject({
      method: 'DELETE',
      url: `/v1/households/${householdId}/pantry/items/${itemId}?baseRevision=2`,
      headers: { ...auth, 'idempotency-key': 'pantry-delete-1' },
    })
    expect(removed.statusCode).toBe(200)
    expect(removed.json()).toEqual({ deleted: true, id: itemId })
  })

  it('replays an idempotent create without duplicating the item', async () => {
    const { app, auth, householdId } = await setup()
    const payload = { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg', location: 'pantry' }
    const first = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-replay-1' }, payload })
    const second = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-replay-1' }, payload })
    expect(second.statusCode).toBe(200)
    expect(second.json().id).toBe(first.json().id)
    const list = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })
    expect(list.json().items).toHaveLength(1)
  })

  it('rejects stale revisions and access from another household', async () => {
    const { app, auth, householdId } = await setup()
    const created = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-conflict-1' },
      payload: { ingredientId: 'salt', displayName: 'Tuz', quantity: 1, unit: 'kg', location: 'pantry' },
    })
    const itemId = created.json().id as string
    const stale = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${itemId}?baseRevision=99`, headers: { ...auth, 'idempotency-key': 'pantry-conflict-2' }, payload: { quantity: 0 },
    })
    expect(stale.statusCode).toBe(409)

    const other = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject: 'pantry-other' }) } })
    const otherAuth = { authorization: `Bearer ${other.json().accessToken}` }
    const forbidden = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: otherAuth })
    expect(forbidden.statusCode).toBe(403)
  })
})
