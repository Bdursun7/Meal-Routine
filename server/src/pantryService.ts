import { createHash, randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import type { HouseholdStore } from './householdTypes.js'
import { canonicalUnit, convertPantryQuantity, parsePantryUnit, roundPantryQuantity, unitsCompatible } from './pantryUnits.js'
import type {
  PantryDraft,
  PantryItem,
  PantryPatch,
  PantryReconcileLine,
  PantryReconcileOperation,
  PantryReconcileResultLine,
  PantryStore,
} from './pantryTypes.js'

const IDEMPOTENCY_MS = 24 * 60 * 60 * 1000

export interface PantryWriteOptions {
  confirmSeparate?: boolean
}

export interface PantryReconcileRequest {
  operation: PantryReconcileOperation
  lines: PantryReconcileLine[]
  confirmSeparate?: boolean
}

export interface PantryService {
  list(accountId: string, householdId: string): Promise<PantryItem[]>
  create(accountId: string, householdId: string, draft: Omit<PantryDraft, 'id'>, key: string, now: Date, options?: PantryWriteOptions): Promise<PantryItem>
  update(accountId: string, householdId: string, itemId: string, patch: PantryPatch, baseRevision: number | undefined, key: string, now: Date, options?: PantryWriteOptions): Promise<PantryItem>
  remove(accountId: string, householdId: string, itemId: string, baseRevision: number | undefined, key: string, now: Date): Promise<{ deleted: true; id: string }>
  reconcile(accountId: string, householdId: string, request: PantryReconcileRequest, key: string, now: Date): Promise<{ lines: PantryReconcileResultLine[]; items: PantryItem[] }>
  clearAccount(accountId: string): Promise<void>
}

export function createPantryService(store: PantryStore, households: HouseholdStore): PantryService {
  return {
    async list(accountId, householdId) {
      await authorize(households, householdId, accountId)
      return store.listPantry(householdId)
    },
    async create(accountId, householdId, draft, key, now, options) {
      await authorize(households, householdId, accountId)
      const normalized = normalizeDraft(draft, options?.confirmSeparate === true)
      return idempotent(store, accountId, key, { draft: normalized, confirmSeparate: options?.confirmSeparate === true }, now, async () => {
        const existing = await store.listPantry(householdId)
        const compatible = existing.find((item) => item.ingredientId === normalized.ingredientId && unitsCompatible(item.unit, normalized.unit))
        if (compatible) {
          const added = convertPantryQuantity(normalized.quantity, normalized.unit, compatible.unit)
          if (added === null) throw new AppError('invalid_unit', 400)
          const minimum = mergeMinimum(compatible, normalized)
          return store.updatePantryItem(householdId, compatible.id, {
            quantity: roundPantryQuantity(compatible.quantity + added),
            displayName: normalized.displayName,
            location: normalized.location,
            minimumQuantity: minimum,
            bestBefore: normalized.bestBefore ?? compatible.bestBefore,
          }, compatible.revision, now)
        }
        const blocked = existing.find((item) => item.ingredientId === normalized.ingredientId)
        if (blocked && options?.confirmSeparate !== true) {
          throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: blocked.unit, incomingUnit: normalized.unit })
        }
        return store.insertPantryItem(householdId, { ...normalized, id: randomUUID() }, now)
      }) as Promise<PantryItem>
    },
    async update(accountId, householdId, itemId, patch, baseRevision, key, now, options) {
      await authorize(households, householdId, accountId)
      const current = await store.getPantryItem(householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      const normalized = normalizePatch(current, patch, options?.confirmSeparate === true)
      return idempotent(store, accountId, key, { itemId, patch: normalized, baseRevision, confirmSeparate: options?.confirmSeparate === true }, now, async () => {
        const latest = await store.getPantryItem(householdId, itemId)
        if (!latest) throw new AppError('not_found', 404)
        if (normalized.unit && !unitsCompatible(latest.unit, normalized.unit) && !options?.confirmSeparate) {
          throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: latest.unit, incomingUnit: normalized.unit })
        }
        return store.updatePantryItem(householdId, itemId, normalized, baseRevision, now)
      }) as Promise<PantryItem>
    },
    async remove(accountId, householdId, itemId, baseRevision, key, now) {
      await authorize(households, householdId, accountId)
      const body = { itemId, baseRevision }
      return idempotent(store, accountId, key, body, now, async () => {
        await store.deletePantryItem(householdId, itemId, baseRevision)
        return { deleted: true as const, id: itemId }
      }) as Promise<{ deleted: true; id: string }>
    },
    async reconcile(accountId, householdId, request, key, now) {
      await authorize(households, householdId, accountId)
      return idempotent(store, accountId, key, request, now, async () => {
        const stored = await store.listPantry(householdId)
        const working = stored.map((item) => ({ ...item }))
        const lines = request.lines.map((line) => applyLine(request.operation, line, working, request.confirmSeparate === true))
        if (request.operation !== 'compute-missing') {
          await persistWorking(store, householdId, stored, working, now)
        }
        const items = request.operation === 'compute-missing' ? stored : await store.listPantry(householdId)
        return { lines, items }
      }) as Promise<{ lines: PantryReconcileResultLine[]; items: PantryItem[] }>
    },
    async clearAccount(accountId) {
      await store.clearAccountPantry(accountId)
    },
  }
}

function applyLine(
  operation: PantryReconcileOperation,
  line: PantryReconcileLine,
  working: PantryItem[],
  confirmSeparate: boolean,
): PantryReconcileResultLine {
  const unit = canonicalUnit(line.unit, confirmSeparate)
  const base = {
    ingredientId: line.ingredientId,
    displayName: line.displayName?.trim() || line.ingredientId,
    quantity: roundPantryQuantity(line.quantity),
    unit: unit ?? line.unit,
    checked: line.checked === true,
    incompatible: false,
    applied: false,
  }
  if (!unit) return { ...base, incompatible: true }
  if (operation === 'compute-missing' && line.checked === true) return base
  const sameIngredient = working.filter((item) => item.ingredientId === line.ingredientId)
  const compatible = sameIngredient.find((item) => unitsCompatible(item.unit, unit))
  if (!compatible) {
    if (operation === 'restock' && (sameIngredient.length === 0 || confirmSeparate)) {
      const created: PantryItem = {
        id: randomUUID(),
        householdId: working[0]?.householdId ?? '',
        ingredientId: line.ingredientId,
        displayName: base.displayName,
        quantity: base.quantity,
        unit,
        location: line.location ?? 'pantry',
        minimumQuantity: null,
        bestBefore: null,
        revision: 0,
        createdAt: '',
        updatedAt: '',
      }
      working.push(created)
      return { ...base, unit, applied: true }
    }
    return { ...base, incompatible: sameIngredient.length > 0 || parsePantryUnit(line.unit).known === false, applied: false }
  }
  const converted = convertPantryQuantity(line.quantity, unit, compatible.unit)
  if (converted === null) return { ...base, incompatible: true }
  if (operation === 'compute-missing') {
    const available = convertPantryQuantity(compatible.quantity, compatible.unit, unit) ?? 0
    const remaining = roundPantryQuantity(Math.max(0, line.quantity - available))
    const consumed = convertPantryQuantity(line.quantity - remaining, unit, compatible.unit) ?? 0
    compatible.quantity = roundPantryQuantity(Math.max(0, compatible.quantity - consumed))
    return { ...base, quantity: remaining, unit, applied: true, incompatible: false }
  }
  if (operation === 'consume') {
    compatible.quantity = roundPantryQuantity(Math.max(0, compatible.quantity - converted))
    return { ...base, unit, applied: true }
  }
  compatible.quantity = roundPantryQuantity(compatible.quantity + converted)
  if (line.displayName) compatible.displayName = base.displayName
  return { ...base, unit, applied: true }
}

async function persistWorking(store: PantryStore, householdId: string, original: PantryItem[], working: PantryItem[], now: Date): Promise<void> {
  const known = new Set(original.map((item) => item.id))
  for (const item of working) {
    if (!known.has(item.id)) {
      await store.insertPantryItem(householdId, {
        id: item.id,
        ingredientId: item.ingredientId,
        displayName: item.displayName,
        quantity: item.quantity,
        unit: item.unit,
        location: item.location,
        minimumQuantity: item.minimumQuantity,
        bestBefore: item.bestBefore,
      }, now)
      continue
    }
    const before = original.find((row) => row.id === item.id)
    if (!before || before.quantity === item.quantity && before.displayName === item.displayName) continue
    await store.updatePantryItem(householdId, item.id, {
      quantity: item.quantity,
      displayName: item.displayName,
    }, before.revision, now)
  }
}

function normalizeDraft(draft: Omit<PantryDraft, 'id'>, allowUnknown: boolean): Omit<PantryDraft, 'id'> {
  const unit = canonicalUnit(draft.unit, allowUnknown)
  if (!unit) throw new AppError('invalid_unit', 400)
  if (!Number.isFinite(draft.quantity) || draft.quantity < 0) throw new AppError('invalid_request', 400)
  const minimum = draft.minimumQuantity
  if (minimum !== null && (!Number.isFinite(minimum) || minimum < 0)) throw new AppError('invalid_request', 400)
  return {
    ...draft,
    ingredientId: draft.ingredientId.trim(),
    displayName: draft.displayName.trim(),
    quantity: roundPantryQuantity(draft.quantity),
    unit,
    minimumQuantity: minimum === null ? null : roundPantryQuantity(minimum),
    bestBefore: normalizeDate(draft.bestBefore),
  }
}

function normalizePatch(current: PantryItem, patch: PantryPatch, allowUnknown: boolean): PantryPatch {
  const next: PantryPatch = { ...patch }
  if (patch.unit !== undefined) {
    const unit = canonicalUnit(patch.unit, allowUnknown)
    if (!unit) throw new AppError('invalid_unit', 400)
    next.unit = unit
    if (patch.quantity === undefined && unitsCompatible(current.unit, unit) && current.unit !== unit) {
      const converted = convertPantryQuantity(current.quantity, current.unit, unit)
      if (converted === null) throw new AppError('invalid_unit', 400)
      next.quantity = converted
      if (patch.minimumQuantity === undefined && current.minimumQuantity !== null) {
        next.minimumQuantity = convertPantryQuantity(current.minimumQuantity, current.unit, unit)
      }
    }
  }
  if (next.quantity !== undefined && (!Number.isFinite(next.quantity) || next.quantity < 0)) throw new AppError('invalid_request', 400)
  if (next.minimumQuantity !== undefined && next.minimumQuantity !== null && (!Number.isFinite(next.minimumQuantity) || next.minimumQuantity < 0)) {
    throw new AppError('invalid_request', 400)
  }
  if (patch.bestBefore !== undefined) next.bestBefore = normalizeDate(patch.bestBefore)
  if (next.quantity !== undefined) next.quantity = roundPantryQuantity(next.quantity)
  if (typeof next.minimumQuantity === 'number') next.minimumQuantity = roundPantryQuantity(next.minimumQuantity)
  return next
}

function mergeMinimum(existing: PantryItem, incoming: Omit<PantryDraft, 'id'>): number | null {
  if (incoming.minimumQuantity === null) return existing.minimumQuantity
  return convertPantryQuantity(incoming.minimumQuantity, incoming.unit, existing.unit)
}

function normalizeDate(value: string | null): string | null {
  if (value === null || value === '') return null
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new AppError('invalid_date', 400)
  const date = new Date(`${value}T00:00:00.000Z`)
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) throw new AppError('invalid_date', 400)
  return value
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
