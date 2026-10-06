import { randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import type { MemberRole } from './repository.js'
import type { PantryDraft, PantryIdempotencyHit, PantryItem, PantryPatch, PantryStore } from './pantryTypes.js'

export function createMemoryPantry(
  members: Map<string, Map<string, MemberRole>>,
  accountHouseholds: (accountId: string) => string[],
): PantryStore {
  const items = new Map<string, PantryItem>()
  const idempotency = new Map<string, PantryIdempotencyHit & { accountId: string; key: string }>()
  const clone = (item: PantryItem): PantryItem => ({ ...item })
  return {
    async listPantry(householdId) {
      return [...items.values()].filter((item) => item.householdId === householdId).sort((a, b) => a.updatedAt.localeCompare(b.updatedAt)).map(clone)
    },
    async getPantryItem(householdId, itemId) {
      const item = items.get(itemId)
      return item && item.householdId === householdId ? clone(item) : null
    },
    async insertPantryItem(householdId, draft, now) {
      if ([...items.values()].some((item) => item.householdId === householdId && item.ingredientId === draft.ingredientId && item.unit === draft.unit)) {
        throw new AppError('pantry_duplicate', 409)
      }
      const item: PantryItem = {
        ...draft,
        id: draft.id || randomUUID(),
        householdId,
        revision: 1,
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
      }
      items.set(item.id, item)
      return clone(item)
    },
    async updatePantryItem(householdId, itemId, patch, baseRevision, now) {
      const current = items.get(itemId)
      if (!current || current.householdId !== householdId) throw new AppError('not_found', 404)
      if (baseRevision !== undefined && baseRevision !== current.revision) throw new AppError('conflict', 409, undefined, { current: clone(current) })
      const next = { ...current, ...patch, revision: current.revision + 1, updatedAt: now.toISOString() }
      if (next.quantity < 0 || (next.minimumQuantity !== null && next.minimumQuantity < 0)) throw new AppError('invalid_request', 400)
      const duplicate = [...items.values()].some((item) => item.id !== itemId && item.householdId === householdId && item.ingredientId === next.ingredientId && item.unit === next.unit)
      if (duplicate) throw new AppError('pantry_duplicate', 409)
      items.set(itemId, next)
      return clone(next)
    },
    async deletePantryItem(householdId, itemId, baseRevision) {
      const current = items.get(itemId)
      if (!current || current.householdId !== householdId) throw new AppError('not_found', 404)
      if (baseRevision !== undefined && baseRevision !== current.revision) throw new AppError('conflict', 409, undefined, { current: clone(current) })
      items.delete(itemId)
    },
    async readPantryIdempotency(accountId, key) {
      const row = idempotency.get(`${accountId}:${key}`)
      return row ? { requestHash: row.requestHash, responseBody: row.responseBody, expiresAt: row.expiresAt } : null
    },
    async writePantryIdempotency(row) {
      idempotency.set(`${row.accountId}:${row.key}`, { ...row })
    },
    async clearAccountPantry(accountId) {
      for (const householdId of accountHouseholds(accountId)) {
        for (const [id, item] of items) if (item.householdId === householdId) items.delete(id)
      }
    },
    async householdForPantryItem(itemId) {
      return items.get(itemId)?.householdId ?? null
    },
    async householdMembers(householdId) {
      return [...(members.get(householdId)?.entries() ?? [])].map(([accountId, role]) => ({ accountId, role }))
    },
  }
}
