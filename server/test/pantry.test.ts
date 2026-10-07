import { describe, expect, it } from 'vitest'
import type { FastifyInstance } from 'fastify'
import { buildApp } from '../src/app.js'
import { buildIngredientIndex, foldIngredientName, resolveIngredientId, searchIngredients, seedIngredients } from '../src/ingredients.js'
import type { MemoryRepository } from '../src/repository.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

type Auth = { authorization: string }

async function signIn(app: FastifyInstance, subject: string): Promise<Auth> {
  const response = await app.inject({ method: 'POST', url: '/v1/auth/apple', payload: { identityToken: identityToken({ subject, givenName: 'Ada' }), givenName: 'Ada' } })
  return { authorization: `Bearer ${response.json().accessToken}` }
}

async function setup(repo: MemoryRepository = memoryRepo(), config = testConfig()) {
  const app = buildApp({ repo, config, verifier: testVerifier() })
  const auth = await signIn(app, 'pantry-owner')
  const household = await app.inject({ method: 'POST', url: '/v1/households', headers: auth, payload: { name: 'Mutfak' } })
  return { app, repo, auth, householdId: household.json().household.id as string }
}

function create(app: FastifyInstance, auth: Auth, householdId: string, key: string, payload: Record<string, unknown>) {
  return app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: { ...auth, 'idempotency-key': key }, payload })
}

function reconcile(app: FastifyInstance, auth: Auth, householdId: string, key: string, payload: Record<string, unknown>) {
  return app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/reconcile-grocery`, headers: { ...auth, 'idempotency-key': key }, payload })
}

async function list(app: FastifyInstance, auth: Auth, householdId: string) {
  return (await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })).json().items as Record<string, unknown>[]
}

const tomato = { ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g', location: 'refrigerator' }

describe('ingredient dictionary', () => {
  const index = buildIngredientIndex(seedIngredients())

  it('resolves dictionary ids, catalog source ids and unambiguous import names only', () => {
    expect(resolveIngredientId(index, 'tomato')).toBe('tomato')
    expect(resolveIngredientId(index, 'tomatoes')).toBe('tomato')
    expect(resolveIngredientId(index, 'pepper')).toBe('blackpepper')
    expect(resolveIngredientId(index, 'peppers')).toBe('peppers')
    expect(resolveIngredientId(index, 'import:domates')).toBe('tomato')
    expect(resolveIngredientId(index, 'import:cherrydomates')).toBe('cherry-tomato')
    expect(resolveIngredientId(index, 'domates')).toBeNull()
    expect(resolveIngredientId(index, 'Domates')).toBeNull()
    expect(resolveIngredientId(index, 'manual:6f1d6a0e-0000-4000-8000-000000000000')).toBeNull()
    expect(resolveIngredientId(index, 'import:domatessosu')).toBeNull()
  })

  it('keeps similar names apart unless the dictionary says otherwise', () => {
    expect(resolveIngredientId(index, 'cherry-tomato')).not.toBe(resolveIngredientId(index, 'tomato'))
    expect(resolveIngredientId(index, 'tomatopaste')).not.toBe('tomato')
    expect(resolveIngredientId(index, 'greenpepper')).not.toBe(resolveIngredientId(index, 'peppers'))
    const thyme = index.byId.get('thyme')!
    const oregano = index.byId.get('oregano')!
    expect(foldIngredientName(thyme.displayName)).not.toBe(foldIngredientName(oregano.displayName))
  })

  it('suggests by name for the picker without deciding identity', () => {
    const hits = searchIngredients(seedIngredients(), 'domat', 20).map((row) => row.id)
    expect(hits[0]).toBe('tomato')
    expect(hits).toContain('cherry-tomato')
    expect(foldIngredientName('Şeker İçi Ğ ö ü ı')).toBe('sekericigoui')
  })

  it('never lets one folded name point at two seed entries', () => {
    const owners = new Map<string, Set<string>>()
    for (const row of seedIngredients()) {
      for (const name of [row.displayName, ...row.synonyms]) {
        const key = foldIngredientName(name)
        owners.set(key, (owners.get(key) ?? new Set()).add(row.id))
      }
    }
    expect([...owners.entries()].filter(([, ids]) => ids.size > 1)).toEqual([])
  })
})

describe('pantry', () => {
  it('creates, lists, updates and deletes a household pantry item with the guide fields', async () => {
    const { app, auth, householdId } = await setup()
    const clientId = '0b7a9f3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b'
    const created = await create(app, auth, householdId, 'pantry-create-1', { ...tomato, id: clientId, minimumQuantity: 200, dateType: 'useBy', dateValue: '2030-01-05' })
    expect(created.statusCode).toBe(200)
    expect(created.json()).toMatchObject({
      id: clientId, householdId, ingredientId: 'tomato', displayName: 'Domates', quantity: 400, unit: 'g',
      location: 'refrigerator', minimumQuantity: 200, dateType: 'useBy', dateValue: '2030-01-05', version: 1,
    })
    expect(created.json().createdAt).toBeTruthy()
    expect(await list(app, auth, householdId)).toHaveLength(1)
    const updated = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${clientId}?baseVersion=1`,
      headers: { ...auth, 'idempotency-key': 'pantry-update-1' }, payload: { quantity: 250, dateType: 'bestBefore', dateValue: '2030-02-01' },
    })
    expect(updated.statusCode).toBe(200)
    expect(updated.json()).toMatchObject({ quantity: 250, minimumQuantity: 200, dateType: 'bestBefore', dateValue: '2030-02-01', version: 2 })
    const cleared = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${clientId}?baseVersion=2`,
      headers: { ...auth, 'idempotency-key': 'pantry-update-2' }, payload: { dateType: null, dateValue: null },
    })
    expect(cleared.json()).toMatchObject({ dateType: null, dateValue: null, version: 3 })
    const removed = await app.inject({ method: 'DELETE', url: `/v1/households/${householdId}/pantry/items/${clientId}?baseVersion=3`, headers: { ...auth, 'idempotency-key': 'pantry-delete-1' } })
    expect(removed.json()).toEqual({ deleted: true, id: clientId })
    expect(await list(app, auth, householdId)).toEqual([])
  })

  it('replays an idempotent create without duplicating the item', async () => {
    const { app, auth, householdId } = await setup()
    const payload = { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg', location: 'pantry' }
    const first = await create(app, auth, householdId, 'pantry-replay-1', payload)
    const second = await create(app, auth, householdId, 'pantry-replay-1', payload)
    expect(second.json()).toEqual(first.json())
    expect(await list(app, auth, householdId)).toHaveLength(1)
    const reused = await create(app, auth, householdId, 'pantry-replay-1', { ...payload, quantity: 2 })
    expect(reused.statusCode).toBe(409)
    expect(reused.json()).toMatchObject({ error: 'idempotency_key_reused', recovery: 'new-key' })
  })

  it('returns the server version on a stale write and refuses other households', async () => {
    const { app, auth, householdId } = await setup()
    const created = await create(app, auth, householdId, 'pantry-conflict-1', { ingredientId: 'salt', displayName: 'Tuz', quantity: 1, unit: 'kg', location: 'pantry' })
    const itemId = created.json().id as string
    const stale = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${itemId}?baseVersion=99`, headers: { ...auth, 'idempotency-key': 'pantry-conflict-2' }, payload: { quantity: 0 },
    })
    expect(stale.statusCode).toBe(409)
    expect(stale.json()).toMatchObject({ error: 'conflict', recovery: 'resolve', current: { quantity: 1, version: 1 } })
    const staleDelete = await app.inject({ method: 'DELETE', url: `/v1/households/${householdId}/pantry/items/${itemId}?baseVersion=7`, headers: { ...auth, 'idempotency-key': 'pantry-conflict-3' } })
    expect(staleDelete.statusCode).toBe(409)
    expect(await list(app, auth, householdId)).toHaveLength(1)

    const otherAuth = await signIn(app, 'pantry-other')
    const otherHousehold = (await app.inject({ method: 'POST', url: '/v1/households', headers: otherAuth, payload: { name: 'Öteki' } })).json().household.id as string
    expect((await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: otherAuth })).statusCode).toBe(403)
    expect((await create(app, otherAuth, householdId, 'pantry-forbidden-write', tomato)).statusCode).toBe(403)
    const patch = await app.inject({ method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${itemId}`, headers: { ...otherAuth, 'idempotency-key': 'pantry-forbidden-patch' }, payload: { quantity: 9 } })
    expect(patch.statusCode).toBe(403)
    const remove = await app.inject({ method: 'DELETE', url: `/v1/households/${householdId}/pantry/items/${itemId}`, headers: { ...otherAuth, 'idempotency-key': 'pantry-forbidden-delete' } })
    expect(remove.statusCode).toBe(403)
    const recon = await reconcile(app, otherAuth, householdId, 'pantry-forbidden-recon', { operation: 'consume', lines: [{ ingredientId: 'salt', quantity: 1, unit: 'kg' }] })
    expect(recon.statusCode).toBe(403)
    const cross = await app.inject({ method: 'PATCH', url: `/v1/households/${otherHousehold}/pantry/items/${itemId}`, headers: { ...otherAuth, 'idempotency-key': 'pantry-cross-patch' }, payload: { quantity: 9 } })
    expect(cross.statusCode).toBe(404)
    const stolenId = await create(app, otherAuth, otherHousehold, 'pantry-cross-id', { ...tomato, id: itemId })
    expect(stolenId.statusCode).toBe(409)
    expect((await list(app, auth, householdId))[0]).toMatchObject({ quantity: 1 })
  })

  it('merges compatible units, keeps incompatible units apart and rejects unknown units', async () => {
    const { app, auth, householdId } = await setup()
    const grams = await create(app, auth, householdId, 'pantry-unit-g', tomato)
    const kilos = await create(app, auth, householdId, 'pantry-unit-kg', { ...tomato, quantity: 1, unit: 'kg' })
    expect(kilos.json()).toMatchObject({ id: grams.json().id, quantity: 1400, unit: 'g', version: 2 })

    const pieces = await create(app, auth, householdId, 'pantry-unit-piece', { ...tomato, quantity: 6, unit: 'adet', location: 'pantry' })
    expect(pieces.statusCode).toBe(409)
    expect(pieces.json()).toMatchObject({ error: 'pantry_unit_choice', recovery: 'choose-unit', existingUnit: 'g', incomingUnit: 'piece' })
    const separate = await create(app, auth, householdId, 'pantry-unit-piece-ok', { ...tomato, quantity: 6, unit: 'piece', confirmSeparate: true })
    expect(separate.json()).toMatchObject({ unit: 'piece', quantity: 6 })
    expect(await list(app, auth, householdId)).toHaveLength(2)

    for (const [key, unit] of [['pantry-unit-bad', 'kova'], ['pantry-unit-bad-forced', 'paket']] as const) {
      const invalid = await create(app, auth, householdId, key, { ingredientId: 'flour', displayName: 'Un', quantity: 1, unit, location: 'pantry', confirmSeparate: true })
      expect(invalid.statusCode).toBe(400)
      expect(invalid.json()).toMatchObject({ error: 'invalid_unit', recovery: 'fix-input' })
    }
    const negative = await create(app, auth, householdId, 'pantry-negative', { ...tomato, quantity: -1 })
    expect(negative.statusCode).toBe(400)
    const minimum = await create(app, auth, householdId, 'pantry-negative-min', { ...tomato, minimumQuantity: -1 })
    expect(minimum.statusCode).toBe(400)

    const toKilo = await app.inject({
      method: 'PATCH', url: `/v1/households/${householdId}/pantry/items/${grams.json().id}`, headers: { ...auth, 'idempotency-key': 'pantry-unit-to-kg' }, payload: { unit: 'kg' },
    })
    expect(toKilo.json()).toMatchObject({ unit: 'kg', quantity: 1.4 })
  })

  it('keeps the two date kinds apart and never invents one', async () => {
    const { app, auth, householdId } = await setup()
    const none = await create(app, auth, householdId, 'pantry-date-none', tomato)
    expect(none.json()).toMatchObject({ dateType: null, dateValue: null })
    const milk = await create(app, auth, householdId, 'pantry-date-useby', { ingredientId: 'milk', displayName: 'Süt', quantity: 1, unit: 'l', location: 'refrigerator', dateType: 'useBy', dateValue: '2030-03-01' })
    const rice = await create(app, auth, householdId, 'pantry-date-bestbefore', { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg', location: 'pantry', dateType: 'bestBefore', dateValue: '2030-03-01' })
    expect(milk.json().dateType).toBe('useBy')
    expect(rice.json().dateType).toBe('bestBefore')
    const cases: [string, Record<string, unknown>, string][] = [
      ['pantry-date-bad', { dateType: 'useBy', dateValue: '2030-13-40' }, 'invalid_date'],
      ['pantry-date-half-type', { dateType: 'useBy' }, 'invalid_date'],
      ['pantry-date-half-value', { dateValue: '2030-01-01' }, 'invalid_date'],
      ['pantry-date-kind', { dateType: 'expires', dateValue: '2030-01-01' }, 'invalid_request'],
      ['pantry-date-legacy', { bestBefore: '2030-01-01' }, 'invalid_request'],
    ]
    for (const [key, extra, error] of cases) {
      const response = await create(app, auth, householdId, key, { ingredientId: 'flour', displayName: 'Un', quantity: 1, unit: 'kg', location: 'pantry', ...extra })
      expect(response.statusCode, key).toBe(400)
      expect(response.json().error, key).toBe(error)
    }
  })

  it('matches by ingredientId only and never by a similar display name', async () => {
    const { app, auth, householdId } = await setup()
    const free = await create(app, auth, householdId, 'pantry-free-text', { ...tomato, ingredientId: 'domates' })
    expect(free.statusCode).toBe(400)
    expect(free.json()).toMatchObject({ error: 'unknown_ingredient', recovery: 'fix-input' })

    const base = await create(app, auth, householdId, 'pantry-id-tomato', tomato)
    const plural = await create(app, auth, householdId, 'pantry-id-tomatoes', { ...tomato, ingredientId: 'tomatoes', quantity: 100 })
    expect(plural.json()).toMatchObject({ id: base.json().id, ingredientId: 'tomato', quantity: 500 })
    const imported = await create(app, auth, householdId, 'pantry-id-import', { ...tomato, ingredientId: 'import:domates', quantity: 100 })
    expect(imported.json()).toMatchObject({ id: base.json().id, quantity: 600 })

    const cherry = await create(app, auth, householdId, 'pantry-id-cherry', { ...tomato, ingredientId: 'cherry-tomato', displayName: 'Domates' })
    expect(cherry.statusCode).toBe(200)
    expect(cherry.json().id).not.toBe(base.json().id)
    const paste = await create(app, auth, householdId, 'pantry-id-paste', { ...tomato, ingredientId: 'tomatopaste', displayName: 'Domates' })
    expect(paste.json().id).not.toBe(base.json().id)

    const register = (key: string, id: string) => app.inject({
      method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...auth, 'idempotency-key': key }, payload: { id, displayName: 'Ev turşusu' },
    })
    const first = await register('ingredient-pickle-1', 'custom:11111111-1111-4111-8111-111111111111')
    const second = await register('ingredient-pickle-2', 'custom:22222222-2222-4222-8222-222222222222')
    expect(first.json()).toMatchObject({ id: 'custom:11111111-1111-4111-8111-111111111111', scope: 'household' })
    const a = await create(app, auth, householdId, 'pantry-pickle-a', { ingredientId: first.json().id, displayName: 'Ev turşusu', quantity: 1, unit: 'piece', location: 'pantry' })
    const b = await create(app, auth, householdId, 'pantry-pickle-b', { ingredientId: second.json().id, displayName: 'Ev turşusu', quantity: 1, unit: 'piece', location: 'pantry' })
    expect(a.json().id).not.toBe(b.json().id)
    const rows = await list(app, auth, householdId)
    expect(rows.filter((row) => row.displayName === 'Domates')).toHaveLength(3)
    expect(rows.filter((row) => row.displayName === 'Ev turşusu')).toHaveLength(2)
  })

  it('lists the dictionary and only creates household ingredients through the controlled flow', async () => {
    const { app, auth, householdId } = await setup()
    const all = await app.inject({ method: 'GET', url: '/v1/ingredients', headers: auth })
    expect(all.statusCode).toBe(200)
    expect(all.json().ingredients.length).toBe(seedIngredients().length)
    expect(all.json().ingredients.find((row: { id: string }) => row.id === 'tomato')).toMatchObject({ displayName: 'Domates', sourceIds: ['tomatoes'], scope: 'dictionary' })
    const search = await app.inject({ method: 'GET', url: '/v1/ingredients?q=domat&limit=5', headers: auth })
    expect(search.json().ingredients[0].id).toBe('tomato')
    expect((await app.inject({ method: 'GET', url: '/v1/ingredients' })).statusCode).toBe(401)

    const freeText = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...auth, 'idempotency-key': 'ingredient-free' }, payload: { id: 'ev-tursusu', displayName: 'Ev turşusu' } })
    expect(freeText.statusCode).toBe(400)
    const seedClash = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...auth, 'idempotency-key': 'ingredient-seed' }, payload: { id: 'tomato', displayName: 'Domates' } })
    expect(seedClash.statusCode).toBe(400)
    const id = 'custom:33333333-3333-4333-8333-333333333333'
    const created = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...auth, 'idempotency-key': 'ingredient-new-1' }, payload: { id, displayName: 'Közlenmiş biber' } })
    const replay = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...auth, 'idempotency-key': 'ingredient-new-2' }, payload: { id, displayName: 'Közlenmiş biber' } })
    expect(replay.json()).toEqual(created.json())
    const scoped = await app.inject({ method: 'GET', url: `/v1/ingredients?householdId=${householdId}&q=kozlen`, headers: auth })
    expect(scoped.json().ingredients.map((row: { id: string }) => row.id)).toContain(id)
    const global = await app.inject({ method: 'GET', url: '/v1/ingredients?q=kozlen', headers: auth })
    expect(global.json().ingredients.map((row: { id: string }) => row.id)).not.toContain(id)

    const otherAuth = await signIn(app, 'ingredient-other')
    const otherHousehold = (await app.inject({ method: 'POST', url: '/v1/households', headers: otherAuth, payload: { name: 'Öteki' } })).json().household.id as string
    expect((await app.inject({ method: 'GET', url: `/v1/ingredients?householdId=${householdId}`, headers: otherAuth })).statusCode).toBe(403)
    const stolen = await app.inject({ method: 'POST', url: `/v1/households/${otherHousehold}/ingredients`, headers: { ...otherAuth, 'idempotency-key': 'ingredient-steal' }, payload: { id, displayName: 'Közlenmiş biber' } })
    expect(stolen.statusCode).toBe(409)
    const borrowed = await create(app, otherAuth, otherHousehold, 'pantry-borrowed-ingredient', { ingredientId: id, displayName: 'Közlenmiş biber', quantity: 1, unit: 'piece', location: 'pantry' })
    expect(borrowed.statusCode).toBe(400)
    expect(borrowed.json().error).toBe('unknown_ingredient')
  })

  it('computes missing grocery quantities without double-applying a replay', async () => {
    const { app, auth, householdId } = await setup()
    await create(app, auth, householdId, 'pantry-recon-stock', tomato)
    await create(app, auth, householdId, 'pantry-recon-egg', { ingredientId: 'egg', displayName: 'Yumurta', quantity: 500, unit: 'g', location: 'refrigerator' })
    const payload = {
      operation: 'compute-missing',
      lines: [
        { ingredientId: 'tomato', displayName: 'Domates', quantity: 1000, unit: 'g', checked: false },
        { ingredientId: 'tomatoes', displayName: 'Domates', quantity: 200, unit: 'g', checked: true },
        { ingredientId: 'eggs', displayName: 'Yumurta', quantity: 6, unit: 'piece', checked: false },
        { ingredientId: 'manual:9d1c0a1e-0000-4000-8000-000000000000', displayName: 'Domates', quantity: 2, unit: 'kg', checked: false },
        { ingredientId: 'cherry-tomato', displayName: 'Cherry domates', quantity: 250, unit: 'g', checked: false },
      ],
    }
    const first = await reconcile(app, auth, householdId, 'pantry-recon-missing', payload)
    const second = await reconcile(app, auth, householdId, 'pantry-recon-missing', payload)
    expect(first.statusCode).toBe(200)
    expect(second.json()).toEqual(first.json())
    const lines = first.json().lines
    expect(lines[0]).toMatchObject({ resolvedIngredientId: 'tomato', quantity: 600, applied: true, incompatible: false })
    expect(lines[1]).toMatchObject({ quantity: 200, checked: true, applied: false })
    expect(lines[2]).toMatchObject({ resolvedIngredientId: 'egg', quantity: 6, incompatible: true, applied: false })
    expect(lines[3]).toMatchObject({ resolvedIngredientId: null, unknownIngredient: true, quantity: 2, applied: false })
    expect(lines[4]).toMatchObject({ resolvedIngredientId: 'cherry-tomato', quantity: 250, applied: false, incompatible: false })
    const stock = await list(app, auth, householdId)
    expect(stock.find((item) => item.ingredientId === 'tomato')).toMatchObject({ quantity: 400, version: 1 })
  })

  it('splits stock across two needs and fully covered needs become zero', async () => {
    const { app, auth, householdId } = await setup()
    await create(app, auth, householdId, 'pantry-split-stock', { ...tomato, quantity: 1, unit: 'kg' })
    const response = await reconcile(app, auth, householdId, 'pantry-split', {
      operation: 'compute-missing',
      lines: [
        { ingredientId: 'tomato', quantity: 600, unit: 'g' },
        { ingredientId: 'tomato', quantity: 0.6, unit: 'kg' },
      ],
    })
    expect(response.json().lines.map((line: { quantity: number }) => line.quantity)).toEqual([0, 0.2])
  })

  it('consumes and restocks pantry once when the same grocery reconcile is retried', async () => {
    const { app, auth, householdId } = await setup()
    await create(app, auth, householdId, 'pantry-consume-stock', { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1000, unit: 'g', location: 'pantry' })
    const consume = { operation: 'consume', lines: [{ ingredientId: 'rice', displayName: 'Pirinç', quantity: 400, unit: 'g' }] }
    const first = await reconcile(app, auth, householdId, 'pantry-consume-1', consume)
    const replay = await reconcile(app, auth, householdId, 'pantry-consume-1', consume)
    expect(first.json().items[0].quantity).toBe(600)
    expect(replay.json()).toEqual(first.json())
    expect((await list(app, auth, householdId))[0]).toMatchObject({ quantity: 600 })
    const restock = { operation: 'restock', lines: [{ ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg' }] }
    const added = await reconcile(app, auth, householdId, 'pantry-restock-1', restock)
    const addedAgain = await reconcile(app, auth, householdId, 'pantry-restock-1', restock)
    expect(added.json().items[0].quantity).toBe(1600)
    expect(addedAgain.json().items[0].quantity).toBe(1600)
    const blocked = await reconcile(app, auth, householdId, 'pantry-restock-piece', { operation: 'restock', lines: [{ ingredientId: 'rice', quantity: 2, unit: 'piece' }] })
    expect(blocked.json().lines[0]).toMatchObject({ incompatible: true, applied: false })
    const unknown = await reconcile(app, auth, householdId, 'pantry-restock-unknown', { operation: 'restock', lines: [{ ingredientId: 'manual:abc', displayName: 'Pirinç', quantity: 1, unit: 'kg' }] })
    expect(unknown.json().lines[0]).toMatchObject({ unknownIngredient: true, applied: false })
    const fresh = await reconcile(app, auth, householdId, 'pantry-restock-new', { operation: 'restock', lines: [{ ingredientId: 'tomatoes', quantity: 3, unit: 'piece' }] })
    expect(fresh.json().lines[0]).toMatchObject({ resolvedIngredientId: 'tomato', applied: true })
    const rows = await list(app, auth, householdId)
    expect(rows).toHaveLength(2)
    expect(rows.find((row) => row.ingredientId === 'tomato')).toMatchObject({ displayName: 'Domates', quantity: 3, unit: 'piece', dateType: null, dateValue: null })
  })

  it('merges a consume with an edit from another device instead of failing or applying twice', async () => {
    const repo = memoryRepo()
    const { app, auth, householdId } = await setup(repo)
    const created = await create(app, auth, householdId, 'pantry-race-stock', { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1000, unit: 'g', location: 'pantry' })
    const original = repo.applyPantryBatch.bind(repo)
    let raced = false
    repo.applyPantryBatch = async (household, batch, now) => {
      if (!raced) {
        raced = true
        const current = await repo.getPantryItem(household, created.json().id)
        await repo.updatePantryItem(household, created.json().id, { quantity: 900 }, current!.version, now)
      }
      return original(household, batch, now)
    }
    const response = await reconcile(app, auth, householdId, 'pantry-race-consume', { operation: 'consume', lines: [{ ingredientId: 'rice', quantity: 400, unit: 'g' }] })
    expect(response.statusCode).toBe(200)
    expect((await list(app, auth, householdId))[0]).toMatchObject({ quantity: 500, version: 3 })
  })

  it('classifies pantry errors for recovery and keeps the V4.1 error body elsewhere', async () => {
    const { app, auth, householdId } = await setup()
    const missingKey = await app.inject({ method: 'POST', url: `/v1/households/${householdId}/pantry/items`, headers: auth, payload: tomato })
    expect(missingKey.json()).toEqual({ error: 'invalid_request', recovery: 'fix-input' })
    const expired = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry` })
    expect(expired.json()).toMatchObject({ error: 'session_expired', recovery: 'reauthenticate' })
    const board = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/board` })
    expect(board.json()).toEqual({ error: 'session_expired' })
    const version = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: { ...auth, 'x-client-api-version': '2' } })
    expect(version.statusCode).toBe(406)
    const ok = await app.inject({ method: 'GET', url: `/v1/households/${householdId}/pantry`, headers: auth })
    expect(ok.headers['x-api-version']).toBe('v1')
    const huge = await reconcile(app, auth, householdId, 'pantry-huge', { operation: 'consume', lines: Array.from({ length: 201 }, () => ({ ingredientId: 'rice', quantity: 1, unit: 'g' })) })
    expect(huge.statusCode).toBe(400)
  })

  it('rate limits pantry writes', async () => {
    const { app, auth, householdId } = await setup(memoryRepo(), testConfig({ rateLimitMax: 3 }))
    const statuses: number[] = []
    for (let index = 0; index < 4; index += 1) {
      statuses.push((await create(app, auth, householdId, `pantry-rate-${index}-key`, tomato)).statusCode)
    }
    expect(statuses.slice(0, 3)).toEqual([200, 200, 200])
    expect(statuses[3]).toBe(429)
  })

  it('applies ownership rules on account deletion, household deletion and export', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const ownerAuth = await signIn(app, 'pantry-delete-owner')
    const householdId = (await app.inject({ method: 'POST', url: '/v1/households', headers: ownerAuth, payload: { name: 'Kiler' } })).json().household.id as string
    const custom = 'custom:44444444-4444-4444-8444-444444444444'
    await app.inject({ method: 'POST', url: `/v1/households/${householdId}/ingredients`, headers: { ...ownerAuth, 'idempotency-key': 'pantry-own-ingredient' }, payload: { id: custom, displayName: 'Ev erişte' } })
    await create(app, ownerAuth, householdId, 'pantry-own-1', { ingredientId: 'lentils', displayName: 'Mercimek', quantity: 1, unit: 'kg', location: 'pantry' })
    await create(app, ownerAuth, householdId, 'pantry-own-2', { ingredientId: custom, displayName: 'Ev erişte', quantity: 1, unit: 'piece', location: 'pantry' })
    const exported = (await app.inject({ method: 'GET', url: '/v1/account/export', headers: ownerAuth })).json()
    expect(exported.pantry).toHaveLength(2)
    expect(exported.pantryIngredients.map((row: { id: string }) => row.id)).toEqual([custom])
    expect(await repo.readPantryIdempotency(exported.account.id, 'pantry-own-1')).not.toBeNull()
    const outsider = await signIn(app, 'pantry-outsider')
    const outsiderExport = (await app.inject({ method: 'GET', url: '/v1/account/export', headers: outsider })).json()
    expect(outsiderExport.pantry).toEqual([])
    expect(JSON.stringify(outsiderExport)).not.toContain('Mercimek')

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ownerAuth })
    expect(removed.json()).toEqual({ deleted: true, household: 'deleted' })
    expect(await repo.listPantry(householdId)).toEqual([])
    expect(await repo.listIngredients(householdId)).toEqual([])
    expect(await repo.readPantryIdempotency(exported.account.id, 'pantry-own-1')).toBeNull()
    expect(await repo.readPantryIdempotency(exported.account.id, 'pantry-own-ingredient')).toBeNull()

    const adaAuth = await signIn(app, 'pantry-keep-owner')
    const beaAuth = await signIn(app, 'pantry-keep-partner')
    const sharedId = (await app.inject({ method: 'POST', url: '/v1/households', headers: adaAuth, payload: { name: 'Ev' } })).json().household.id as string
    await create(app, adaAuth, sharedId, 'pantry-keep-item', { ingredientId: 'beans', displayName: 'Fasulye', quantity: 2, unit: 'kg', location: 'pantry' })
    const invite = await app.inject({ method: 'POST', url: `/v1/households/${sharedId}/invites`, headers: adaAuth })
    const code = invite.json().household.invites[0].code as string
    expect((await app.inject({ method: 'POST', url: `/v1/invites/${code}/accept`, headers: beaAuth })).statusCode).toBe(200)
    expect((await app.inject({ method: 'DELETE', url: '/v1/account', headers: adaAuth })).json().household).toBe('left')
    const remaining = await list(app, beaAuth, sharedId)
    expect(remaining).toHaveLength(1)
    expect(remaining[0]).toMatchObject({ displayName: 'Fasulye' })

    expect((await app.inject({ method: 'DELETE', url: `/v1/households/${sharedId}`, headers: beaAuth })).statusCode).toBe(200)
    expect(await repo.listPantry(sharedId)).toEqual([])

    const solo = await signIn(app, 'pantry-leave-owner')
    const soloHousehold = (await app.inject({ method: 'POST', url: '/v1/households', headers: solo, payload: { name: 'Tek' } })).json().household.id as string
    await create(app, solo, soloHousehold, 'pantry-leave-item', { ingredientId: 'rice', displayName: 'Pirinç', quantity: 1, unit: 'kg', location: 'pantry' })
    expect((await app.inject({ method: 'POST', url: `/v1/households/${soloHousehold}/leave`, headers: solo })).statusCode).toBe(200)
    expect(await repo.listPantry(soloHousehold)).toEqual([])
    await app.close()
  })
})
