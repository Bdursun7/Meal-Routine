import { createHash, randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import type { HouseholdStore } from './householdTypes.js'
import type { PantryDraft, PantryItem, PantryPatch, PantryStore } from './pantryTypes.js'

const IDEMPOTENCY_MS = 24 * 60 * 60 * 1000

export interface PantryService {
  list(accountId: string, householdId: string): Promise<PantryItem[]>
  create(accountId: string, householdId: string, draft: Omit<PantryDraft, 'id'>, key: string, now: Date): Promise<PantryItem>
  update(accountId: string, householdId: string, itemId: string, patch: PantryPatch, baseRevision: number | undefined, key: string, now: Date): Promise<PantryItem>
  remove(accountId: string, householdId: string, itemId: string, baseRevision: number | undefined, key: string, now: Date): Promise<{ deleted: true; id: string }>
  clearAccount(accountId: string): Promise<void>
}

export function createPantryService(store: PantryStore, households: HouseholdStore): PantryService {
  return {
    async list(accountId, householdId) {
      await authorize(households, householdId, accountId)
      return store.listPantry(householdId)
    },
    async create(accountId, householdId, draft, key, now) {
      await authorize(households, householdId, accountId)
      return idempotent(store, accountId, key, draft, now, async () => {
        const body = { ...draft, id: randomUUID() }
        return store.insertPantryItem(householdId, body, now)
      }) as Promise<PantryItem>
    },
    async update(accountId, householdId, itemId, patch, baseRevision, key, now) {
      await authorize(households, householdId, accountId)
      const body = { itemId, patch, baseRevision }
      return idempotent(store, accountId, key, body, now, async () => store.updatePantryItem(householdId, itemId, patch, baseRevision, now)) as Promise<PantryItem>
    },
    async remove(accountId, householdId, itemId, baseRevision, key, now) {
      await authorize(households, householdId, accountId)
      const body = { itemId, baseRevision }
      return idempotent(store, accountId, key, body, now, async () => {
        await store.deletePantryItem(householdId, itemId, baseRevision)
        return { deleted: true as const, id: itemId }
      }) as Promise<{ deleted: true; id: string }>
    },
    async clearAccount(accountId) {
      await store.clearAccountPantry(accountId)
    },
  }
}

async function authorize(households: HouseholdStore, householdId: string, accountId: string): Promise<void> {
  await households.transaction(async (tx) => {
    const household = await tx.household(householdId)
    if (!household || household.deletedAt) throw new AppError('not_found', 404)
    const members = await tx.members(householdId)
    if (!members.some((member) => member.accountId === accountId)) throw new AppError('forbidden', 403)
  })
}

async function idempotent<T>(store: PantryStore, accountId: string, key: string, body: unknown, now: Date, work: () => Promise<T>): Promise<T> {
  if (!key || key.length < 8 || key.length > 200) throw new AppError('invalid_request', 400)
  const requestHash = createHash('sha256').update(stable(body)).digest('hex')
  const existing = await store.readPantryIdempotency(accountId, key)
  if (existing && existing.expiresAt.getTime() > now.getTime()) {
    if (existing.requestHash !== requestHash) throw new AppError('idempotency_key_reused', 409)
    return existing.responseBody as T
  }
  const result = await work()
  await store.writePantryIdempotency({
    accountId,
    key,
    requestHash,
    responseBody: result,
    expiresAt: new Date(now.getTime() + IDEMPOTENCY_MS),
  })
  return result
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(',')}}`
  }
  return JSON.stringify(value) ?? 'null'
}
