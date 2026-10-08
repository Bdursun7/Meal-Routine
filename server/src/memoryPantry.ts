import { randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import { cloneIngredient, seedIngredients, type Ingredient } from './ingredients.js'
import type { MemberRole } from './repository.js'
import { pantryTimestamp, type PantryDraft, type PantryIdempotencyHit, type PantryItem, type PantryPatch, type PantryStore } from './pantryTypes.js'
import { parsePantryUnit } from './pantryUnits.js'

type IdempotencyRow = PantryIdempotencyHit & { accountId: string; key: string; householdId: string | null }

/** Mirrors the `unit_bucket` column (0013): mass and volume units share a row, other units do not. */
export function unitBucket(unit: string): string {
  return parsePantryUnit(unit).family ?? unit
}

export function createMemoryPantry(
  members: Map<string, Map<string, MemberRole>>,
  _accountHouseholds: (accountId: string) => string[],
): PantryStore {
  const items = new Map<string, PantryItem>()
  const idempotency = new Map<string, IdempotencyRow>()
  const ingredients = new Map<string, Ingredient>(seedIngredients().map((row) => [row.id, row]))
  const clone = (item: PantryItem): PantryItem => ({ ...item })

  function duplicate(householdId: string, ingredientId: string, unit: string, except?: string): boolean {
    return [...items.values()].some((item) => item.id !== except && item.householdId === householdId && item.ingredientId === ingredientId && unitBucket(item.unit) === unitBucket(unit))
  }

  function requireIngredient(id: string): void {
    if (!ingredients.has(id)) throw new AppError('unknown_ingredient', 400)
  }

  function build(householdId: string, draft: PantryDraft, now: Date): PantryItem {
    requireIngredient(draft.ingredientId)
    if (duplicate(householdId, draft.ingredientId, draft.unit)) throw new AppError('pantry_duplicate', 409)
    return { ...draft, id: draft.id || randomUUID(), householdId, version: 1, createdAt: pantryTimestamp(now), updatedAt: pantryTimestamp(now) }
  }

  function patched(current: PantryItem, patch: PantryPatch, now: Date): PantryItem {
    const next = { ...current, ...patch, version: current.version + 1, updatedAt: pantryTimestamp(now) }
    if (next.quantity < 0 || (next.minimumQuantity !== null && next.minimumQuantity < 0)) throw new AppError('invalid_request', 400)
    if ((next.dateType === null) !== (next.dateValue === null)) throw new AppError('invalid_date', 400)
    requireIngredient(next.ingredientId)
    if (duplicate(current.householdId, next.ingredientId, next.unit, current.id)) throw new AppError('pantry_duplicate', 409)
    return next
  }

  return {
    async listPantry(householdId) {
      return [...items.values()].filter((item) => item.householdId === householdId).sort((a, b) => a.updatedAt.localeCompare(b.updatedAt)).map(clone)
    },
    async getPantryItem(householdId, itemId) {
      const item = items.get(itemId)
      return item && item.householdId === householdId ? clone(item) : null
    },
    async insertPantryItem(householdId, draft, now) {
      const item = build(householdId, draft, now)
      items.set(item.id, item)
      return clone(item)
    },
    async updatePantryItem(householdId, itemId, patch, baseVersion, now) {
      const current = items.get(itemId)
      if (!current || current.householdId !== householdId) throw new AppError('not_found', 404)
      if (baseVersion !== undefined && baseVersion !== current.version) throw new AppError('conflict', 409, undefined, { current: clone(current) })
      const next = patched(current, patch, now)
      items.set(itemId, next)
      return clone(next)
    },
    async deletePantryItem(householdId, itemId, baseVersion) {
      const current = items.get(itemId)
      if (!current || current.householdId !== householdId) throw new AppError('not_found', 404)
      if (baseVersion !== undefined && baseVersion !== current.version) throw new AppError('conflict', 409, undefined, { current: clone(current) })
      items.delete(itemId)
    },
    async applyPantryBatch(householdId, batch, now) {
      const staged = new Map<string, PantryItem>()
      for (const update of batch.updates) {
        const current = items.get(update.id)
        if (!current || current.householdId !== householdId) throw new AppError('conflict', 409)
        if (current.version !== update.baseVersion) throw new AppError('conflict', 409, undefined, { current: clone(current) })
        staged.set(update.id, patched(current, update.patch, now))
      }
      const created = batch.inserts.map((draft) => build(householdId, draft, now))
      for (const [id, item] of staged) items.set(id, item)
      for (const item of created) items.set(item.id, item)
    },
    async readPantryIdempotency(accountId, key) {
      const row = idempotency.get(`${accountId}:${key}`)
      return row ? { requestHash: row.requestHash, responseBody: row.responseBody, expiresAt: row.expiresAt } : null
    },
    async writePantryIdempotency(row) {
      for (const [key, existing] of idempotency) if (existing.expiresAt.getTime() <= Date.now()) idempotency.delete(key)
      idempotency.set(`${row.accountId}:${row.key}`, { ...row })
    },
    async clearAccountPantry(accountId) {
      for (const [key, row] of idempotency) if (row.accountId === accountId) idempotency.delete(key)
    },
    async deleteHouseholdPantry(householdId) {
      for (const [id, item] of items) if (item.householdId === householdId) items.delete(id)
      for (const [id, row] of ingredients) if (row.householdId === householdId) ingredients.delete(id)
      for (const [key, row] of idempotency) if (row.householdId === householdId) idempotency.delete(key)
    },
    async householdForPantryItem(itemId) {
      return items.get(itemId)?.householdId ?? null
    },
    async householdMembers(householdId) {
      return [...(members.get(householdId)?.entries() ?? [])].map(([accountId, role]) => ({ accountId, role }))
    },
    async listIngredients(householdId) {
      return [...ingredients.values()].filter((row) => row.householdId === householdId).map(cloneIngredient)
    },
    async getIngredient(id) {
      const row = ingredients.get(id)
      return row ? cloneIngredient(row) : null
    },
    async insertIngredient(ingredient) {
      if (ingredients.has(ingredient.id)) throw new AppError('ingredient_conflict', 409)
      ingredients.set(ingredient.id, cloneIngredient(ingredient))
      return cloneIngredient(ingredient)
    },
  }
}
