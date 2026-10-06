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
    const forbiddenWrite = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...otherAuth, 'idempotency-key': 'pantry-forbidden-write' },
      payload: { ingredientId: 'salt', displayName: 'Tuz', quantity: 1, unit: 'kg', location: 'pantry' },
    })
    expect(forbiddenWrite.statusCode).toBe(403)
    expect(stale.json().error).toBe('conflict')
    expect(stale.json().current.quantity).toBe(1)
  })

  it('merges compatible units and keeps incompatible units apart', async () => {
    const { app, auth, householdId } = await setup()
    const grams = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-unit-g' },
      payload: { ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g', location: 'refrigerator' },
    })
    const kilos = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-unit-kg' },
      payload: { ingredientId: 'tomato', displayName: 'Domates', quantity: 1, unit: 'kg', location: 'refrigerator' },
    })
    expect(kilos.statusCode).toBe(200)
    expect(kilos.json().id).toBe(grams.json().id)
    expect(kilos.json().quantity).toBe(1400)
    expect(kilos.json().unit).toBe('g')

    const pieces = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-unit-piece' },
      payload: { ingredientId: 'tomato', displayName: 'Domates', quantity: 6, unit: 'piece', location: 'pantry' },
    })
    expect(pieces.statusCode).toBe(409)
    expect(pieces.json().error).toBe('pantry_unit_choice')
    const separate = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-unit-piece-ok' },
      payload: { ingredientId: 'tomato', displayName: 'Domates', quantity: 6, unit: 'piece', location: 'pantry', confirmSeparate: true },
    })
    expect(separate.statusCode).toBe(200)
    expect(separate.json().unit).toBe('piece')
    const list = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })
    expect(list.json().items).toHaveLength(2)

    const invalid = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-unit-bad' },
      payload: { ingredientId: 'flour', displayName: 'Un', quantity: 1, unit: 'kova', location: 'pantry' },
    })
    expect(invalid.statusCode).toBe(400)
    expect(invalid.json().error).toBe('invalid_unit')
    const badDate = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-date-bad' },
      payload: { ingredientId: 'flour', displayName: 'Un', quantity: 1, unit: 'kg', location: 'pantry', bestBefore: '2026-13-40' },
    })
    expect(badDate.statusCode).toBe(400)
    expect(badDate.json().error).toBe('invalid_date')
  })

  it('computes missing grocery quantities without double-applying a replay', async () => {
    const { app, auth, householdId } = await setup()
    await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-recon-stock' },
      payload: { ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g', location: 'refrigerator' },
    })
    await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-recon-egg' },
      payload: { ingredientId: 'egg', displayName: 'Yumurta', quantity: 500, unit: 'g', location: 'refrigerator' },
    })
    const payload = {
      operation: 'compute-missing',
      lines: [
        { ingredientId: 'tomato', displayName: 'Domates', quantity: 1000, unit: 'g', checked: false },
        { ingredientId: 'tomato', displayName: 'Domates', quantity: 200, unit: 'g', checked: true },
        { ingredientId: 'egg', displayName: 'Yumurta', quantity: 6, unit: 'piece', checked: false },
      ],
    }
    const first = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-recon-missing' }, payload,
    })
    const second = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-recon-missing' }, payload,
    })
    expect(first.statusCode).toBe(200)
    expect(second.json()).toEqual(first.json())
    const lines = first.json().lines
    expect(lines[0]).toMatchObject({ ingredientId: 'tomato', quantity: 600, applied: true, incompatible: false })
    expect(lines[1]).toMatchObject({ quantity: 200, checked: true, applied: false })
    expect(lines[2]).toMatchObject({ ingredientId: 'egg', quantity: 6, incompatible: true, applied: false })
    const stock = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })
    expect(stock.json().items.find((item: { ingredientId: string }) => item.ingredientId === 'tomato').quantity).toBe(400)
  })

  it('consumes and restocks pantry once when the same grocery reconcile is retried', async () => {
    const { app, auth, householdId } = await setup()
    await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': 'pantry-consume-stock' },
      payload: { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1000, unit: 'g', location: 'pantry' },
    })
    const consume = {
      operation: 'consume',
      lines: [{ ingredientId: 'rice', displayName: 'Pirinç', quantity: 400, unit: 'g' }],
    }
    const first = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-consume-1' }, payload: consume,
    })
    const replay = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-consume-1' }, payload: consume,
    })
    expect(first.statusCode).toBe(200)
    expect(replay.json().items[0].quantity).toBe(600)
    expect(first.json().items[0].quantity).toBe(600)
    const restock = {
      operation: 'restock',
      lines: [{ ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg' }],
    }
    const added = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-restock-1' }, payload: restock,
    })
    const addedAgain = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-restock-1' }, payload: restock,
    })
    expect(added.json().items[0].quantity).toBe(1600)
    expect(addedAgain.json().items[0].quantity).toBe(1600)
    const blocked = await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': 'pantry-restock-piece' },
      payload: { operation: 'restock', lines: [{ ingredientId: 'rice', displayName: 'Pirinç', quantity: 2, unit: 'piece' }] },
    })
    expect(blocked.json().lines[0].incompatible).toBe(true)
    expect(blocked.json().items).toHaveLength(1)
  })

  it('deletes pantry with a solo household and keeps it when a partner remains', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const owner = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject: 'pantry-delete-owner' }) } })
    const ownerAuth = { authorization: `Bearer ${owner.json().accessToken}` }
    const household = await app.inject({ method: 'POST', url: '/v1/households', headers: ownerAuth, payload: { name: 'Kiler' } })
    const householdId = household.json().household.id as string
    await app.inject({
      method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...ownerAuth, 'idempotency-key': 'pantry-own-1' },
      payload: { ingredientId: 'lentil', displayName: 'Mercimek', quantity: 1, unit: 'kg', location: 'pantry' },
    })
    const exported = await app.inject({ method: 'GET', url: '/v1/account/export', headers: ownerAuth })
    expect(exported.json().pantry).toHaveLength(1)
    expect(JSON.stringify(exported.json().pantry)).toContain('Mercimek')
    const outsider = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject: 'pantry-outsider' }) } })
    const outsiderExport = await app.inject({ method: 'GET', url: '/v1/account/export', headers: { authorization: `Bearer ${outsider.json().accessToken}` } })
    expect(outsiderExport.json().pantry).toEqual([])
    expect(JSON.stringify(outsiderExport.json())).not.toContain('Mercimek')

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ownerAuth })
    expect(removed.json()).toEqual({ deleted: true, household: 'deleted' })
    expect(await repo.listPantry(householdId)).toEqual([])

    const ada = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject: 'pantry-keep-owner' }) } })
    const bea = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject: 'pantry-keep-partner' }) } })
    const adaAuth = { authorization: `Bearer ${ada.json().accessToken}` }
    const beaAuth = { authorization: `Bearer ${bea.json().accessToken}` }
    const shared = await app.inject({ method: 'POST', url: '/v1/households', headers: adaAuth, payload: { name: 'Ev' } })
    const sharedId = shared.json().household.id as string
    await app.inject({
      method: 'POST', url: `/v1/households/${sharedId}/pantry/items`, headers: { ...adaAuth, 'idempotency-key': 'pantry-keep-item' },
      payload: { ingredientId: 'bean', displayName: 'Fasulye', quantity: 2, unit: 'kg', location: 'pantry' },
    })
    const invite = await app.inject({ method: 'POST', url: `/v1/households/${sharedId}/invites`, headers: adaAuth })
    const code = invite.json().household.invites[0].code as string
    expect((await app.inject({ method: 'POST', url: `/v1/invites/${code}/accept`, headers: beaAuth })).statusCode).toBe(200)
    expect((await app.inject({ method: 'DELETE', url: '/v1/account', headers: adaAuth })).json().household).toBe('left')
    const remaining = await app.inject({ method: 'GET', url: `/v1/households/${sharedId}/pantry`, headers: beaAuth })
    expect(remaining.statusCode).toBe(200)
    expect(remaining.json().items).toHaveLength(1)
    expect(remaining.json().items[0].displayName).toBe('Fasulye')
    await app.close()
  })
})
