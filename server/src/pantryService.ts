import { createHash, randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import type { HouseholdStore } from './householdTypes.js'
import {
  buildIngredientIndex,
  CUSTOM_INGREDIENT_PATTERN,
  resolveIngredientId,
  searchIngredients,
  type Ingredient,
  type IngredientIndex,
} from './ingredients.js'
import { canonicalUnit, convertPantryQuantity, roundPantryQuantity, unitsCompatible } from './pantryUnits.js'
import type {
  PantryDateType,
  PantryDraft,
  PantryItem,
  PantryPatch,
  PantryReconcileLine,
  PantryReconcileOperation,
  PantryReconcileResultLine,
  PantryStore,
} from './pantryTypes.js'

const IDEMPOTENCY_MS = 24 * 60 * 60 * 1000
const STALE_RETRIES = 3

export interface PantryWriteOptions {
  confirmSeparate?: boolean
}

export interface PantryReconcileRequest {
  operation: PantryReconcileOperation
  lines: PantryReconcileLine[]
  confirmSeparate?: boolean
}

export type PantryCreateInput = Omit<PantryDraft, 'id'> & { id?: string }

export interface PantryService {
  list(accountId: string, householdId: string): Promise<PantryItem[]>
  create(accountId: string, householdId: string, draft: PantryCreateInput, key: string, now: Date, options?: PantryWriteOptions): Promise<PantryItem>
  update(accountId: string, householdId: string, itemId: string, patch: PantryPatch, baseVersion: number | undefined, key: string, now: Date, options?: PantryWriteOptions): Promise<PantryItem>
  remove(accountId: string, householdId: string, itemId: string, baseVersion: number | undefined, key: string, now: Date): Promise<{ deleted: true; id: string }>
  reconcile(accountId: string, householdId: string, request: PantryReconcileRequest, key: string, now: Date): Promise<{ lines: PantryReconcileResultLine[]; items: PantryItem[] }>
  ingredients(accountId: string, householdId: string | null, query: string, limit: number): Promise<Ingredient[]>
  registerIngredient(accountId: string, householdId: string, input: { id: string; displayName: string }, key: string, now: Date): Promise<Ingredient>
  clearAccount(accountId: string): Promise<void>
  deleteHousehold(householdId: string): Promise<void>
}

/** Tells the client which recovery path an error belongs to. */
export function pantryRecovery(code: string): string | undefined {
  switch (code) {
    case 'conflict':
      return 'resolve'
    case 'pantry_unit_choice':
      return 'choose-unit'
    case 'unknown_ingredient':
    case 'invalid_unit':
    case 'invalid_date':
    case 'invalid_request':
    case 'pantry_duplicate':
    case 'ingredient_conflict':
      return 'fix-input'
    case 'idempotency_key_reused':
      return 'new-key'
    case 'forbidden':
    case 'not_found':
      return 'refresh-household'
    case 'rate_limited':
      return 'retry-later'
    case 'session_expired':
      return 'reauthenticate'
    default:
      return undefined
  }
}

export function createPantryService(store: PantryStore, households: HouseholdStore): PantryService {
  let globalIndex: IngredientIndex | null = null
  let globalEntries: Ingredient[] = []

  async function dictionary(householdId: string | null): Promise<{ index: IngredientIndex; customs: Ingredient[] }> {
    if (!globalIndex) {
      globalEntries = await store.listIngredients(null)
      globalIndex = buildIngredientIndex(globalEntries)
    }
    const customs = householdId ? await store.listIngredients(householdId) : []
    return { index: globalIndex, customs }
  }

  async function resolver(householdId: string): Promise<(raw: string) => Ingredient | null> {
    const { index, customs } = await dictionary(householdId)
    const own = new Map(customs.map((row) => [row.id, row]))
    return (raw) => {
      const id = resolveIngredientId(index, raw)
      if (id) return index.byId.get(id) ?? null
      return own.get(raw.trim()) ?? null
    }
  }

  return {
    async list(accountId, householdId) {
      await authorize(households, householdId, accountId)
      return store.listPantry(householdId)
    },
    async create(accountId, householdId, draft, key, now, options) {
      await authorize(households, householdId, accountId)
      const confirmSeparate = options?.confirmSeparate === true
      const resolve = await resolver(householdId)
      const normalized = normalizeDraft(draft, resolve)
      return idempotent(store, accountId, householdId, key, { draft: normalized, confirmSeparate }, now, async () => {
        if (normalized.id) {
          const owner = await store.householdForPantryItem(normalized.id)
          if (owner && owner !== householdId) throw new AppError('pantry_duplicate', 409)
          const existing = owner ? await store.getPantryItem(householdId, normalized.id) : null
          if (existing) return existing
        }
        return withFreshState(async () => {
          const rows = await store.listPantry(householdId)
          const compatible = rows.find((item) => item.ingredientId === normalized.ingredientId && unitsCompatible(item.unit, normalized.unit))
          if (compatible) {
            const added = convertPantryQuantity(normalized.quantity, normalized.unit, compatible.unit)
            if (added === null) throw new AppError('invalid_unit', 400)
            const hasDate = normalized.dateType !== null
            return store.updatePantryItem(householdId, compatible.id, {
              quantity: roundPantryQuantity(compatible.quantity + added),
              displayName: normalized.displayName,
              location: normalized.location,
              minimumQuantity: mergeMinimum(compatible, normalized),
              dateType: hasDate ? normalized.dateType : compatible.dateType,
              dateValue: hasDate ? normalized.dateValue : compatible.dateValue,
            }, compatible.version, now)
          }
          const blocked = rows.find((item) => item.ingredientId === normalized.ingredientId)
          if (blocked && !confirmSeparate) {
            throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: blocked.unit, incomingUnit: normalized.unit, current: blocked })
          }
          return store.insertPantryItem(householdId, { ...normalized, id: normalized.id ?? randomUUID() }, now)
        })
      }) as Promise<PantryItem>
    },
    async update(accountId, householdId, itemId, patch, baseVersion, key, now, options) {
      await authorize(households, householdId, accountId)
      const current = await store.getPantryItem(householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      const resolve = await resolver(householdId)
      const confirmSeparate = options?.confirmSeparate === true
      const normalized = normalizePatch(current, patch, resolve)
      return idempotent(store, accountId, householdId, key, { itemId, patch: normalized, baseVersion, confirmSeparate }, now, async () => {
        const latest = await store.getPantryItem(householdId, itemId)
        if (!latest) throw new AppError('not_found', 404)
        if (baseVersion !== undefined && baseVersion !== latest.version) throw new AppError('conflict', 409, undefined, { current: latest })
        if (normalized.unit && !unitsCompatible(latest.unit, normalized.unit) && !confirmSeparate) {
          throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: latest.unit, incomingUnit: normalized.unit, current: latest })
        }
        return store.updatePantryItem(householdId, itemId, normalized, baseVersion, now)
      }) as Promise<PantryItem>
    },
    async remove(accountId, householdId, itemId, baseVersion, key, now) {
      await authorize(households, householdId, accountId)
      return idempotent(store, accountId, householdId, key, { itemId, baseVersion }, now, async () => {
        await store.deletePantryItem(householdId, itemId, baseVersion)
        return { deleted: true as const, id: itemId }
      }) as Promise<{ deleted: true; id: string }>
    },
    async reconcile(accountId, householdId, request, key, now) {
      await authorize(households, householdId, accountId)
      const resolve = await resolver(householdId)
      return idempotent(store, accountId, householdId, key, request, now, async () => {
        // Consume and restock are deltas, so a concurrent edit is merged by recomputing on fresh stock.
        return withFreshState(async () => {
          const stored = await store.listPantry(householdId)
          const working = stored.map((item) => ({ ...item }))
          const lines = request.lines.map((line) => applyLine(request.operation, line, working, householdId, request.confirmSeparate === true, resolve))
          if (request.operation === 'compute-missing') return { lines, items: stored }
          await persistWorking(store, householdId, stored, working, now)
          return { lines, items: await store.listPantry(householdId) }
        })
      }) as Promise<{ lines: PantryReconcileResultLine[]; items: PantryItem[] }>
    },
    async ingredients(accountId, householdId, query, limit) {
      if (householdId) await authorize(households, householdId, accountId)
      const { customs } = await dictionary(householdId)
      const entries = [...globalEntries, ...customs]
      return query ? searchIngredients(entries, query, limit) : entries.slice(0, limit)
    },
    async registerIngredient(accountId, householdId, input, key, now) {
      await authorize(households, householdId, accountId)
      const id = input.id.trim().toLowerCase()
      const displayName = input.displayName.trim()
      if (!CUSTOM_INGREDIENT_PATTERN.test(id)) throw new AppError('invalid_request', 400)
      if (!displayName || displayName.length > 160) throw new AppError('invalid_request', 400)
      return idempotent(store, accountId, householdId, key, { register: id, displayName }, now, async () => {
        const existing = await store.getIngredient(id)
        if (existing) {
          if (existing.householdId !== householdId) throw new AppError('ingredient_conflict', 409)
          return existing
        }
        return store.insertIngredient({ id, householdId, displayName, synonyms: [], sourceIds: [] }, now)
      }) as Promise<Ingredient>
    },
    async clearAccount(accountId) {
      await store.clearAccountPantry(accountId)
    },
    async deleteHousehold(householdId) {
      await store.deleteHouseholdPantry(householdId)
    },
  }
}

async function withFreshState<T>(work: () => Promise<T>): Promise<T> {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await work()
    } catch (error) {
      if (attempt >= STALE_RETRIES || !(error instanceof AppError) || error.code !== 'conflict') throw error
    }
  }
}

function applyLine(
  operation: PantryReconcileOperation,
  line: PantryReconcileLine,
  working: PantryItem[],
  householdId: string,
  confirmSeparate: boolean,
  resolve: (raw: string) => Ingredient | null,
): PantryReconcileResultLine {
  const unit = canonicalUnit(line.unit)
  const ingredient = resolve(line.ingredientId)
  const base: PantryReconcileResultLine = {
    ingredientId: line.ingredientId,
    resolvedIngredientId: ingredient?.id ?? null,
    displayName: line.displayName?.trim() || ingredient?.displayName || line.ingredientId,
    quantity: roundPantryQuantity(line.quantity),
    unit: unit ?? line.unit,
    checked: line.checked === true,
    incompatible: false,
    unknownIngredient: ingredient === null,
    applied: false,
  }
  if (operation === 'compute-missing' && line.checked === true) return base
  if (!ingredient) return base
  if (!unit) return { ...base, incompatible: true }
  const sameIngredient = working.filter((item) => item.ingredientId === ingredient.id)
  const compatible = sameIngredient.find((item) => unitsCompatible(item.unit, unit))
  if (!compatible) {
    if (operation === 'restock' && (sameIngredient.length === 0 || confirmSeparate)) {
      working.push({
        id: randomUUID(),
        householdId,
        ingredientId: ingredient.id,
        displayName: base.displayName,
        quantity: base.quantity,
        unit,
        location: line.location ?? 'pantry',
        minimumQuantity: null,
        dateType: null,
        dateValue: null,
        version: 0,
        createdAt: '',
        updatedAt: '',
      })
      return { ...base, applied: true }
    }
    return { ...base, incompatible: sameIngredient.length > 0 }
  }
  const converted = convertPantryQuantity(line.quantity, unit, compatible.unit)
  if (converted === null) return { ...base, incompatible: true }
  if (operation === 'compute-missing') {
    const available = convertPantryQuantity(compatible.quantity, compatible.unit, unit) ?? 0
    const remaining = roundPantryQuantity(Math.max(0, line.quantity - available))
    const consumed = convertPantryQuantity(line.quantity - remaining, unit, compatible.unit) ?? 0
    compatible.quantity = roundPantryQuantity(Math.max(0, compatible.quantity - consumed))
    return { ...base, quantity: remaining, applied: true }
  }
  if (operation === 'consume') {
    compatible.quantity = roundPantryQuantity(Math.max(0, compatible.quantity - converted))
    return { ...base, applied: true }
  }
  compatible.quantity = roundPantryQuantity(compatible.quantity + converted)
  return { ...base, applied: true }
}

async function persistWorking(store: PantryStore, householdId: string, original: PantryItem[], working: PantryItem[], now: Date): Promise<void> {
  const known = new Map(original.map((item) => [item.id, item]))
  const inserts: PantryDraft[] = []
  const updates: { id: string; baseVersion: number; patch: PantryPatch }[] = []
  for (const item of working) {
    const before = known.get(item.id)
    if (!before) {
      inserts.push({
        id: item.id,
        ingredientId: item.ingredientId,
        displayName: item.displayName,
        quantity: item.quantity,
        unit: item.unit,
        location: item.location,
        minimumQuantity: null,
        dateType: null,
        dateValue: null,
      })
    } else if (before.quantity !== item.quantity) {
      updates.push({ id: item.id, baseVersion: before.version, patch: { quantity: item.quantity } })
    }
  }
  if (inserts.length || updates.length) await store.applyPantryBatch(householdId, { inserts, updates }, now)
}

type Resolve = (raw: string) => Ingredient | null

function normalizeDraft(draft: PantryCreateInput, resolve: Resolve): PantryCreateInput {
  const ingredient = resolve(draft.ingredientId)
  if (!ingredient) throw new AppError('unknown_ingredient', 400)
  const unit = canonicalUnit(draft.unit)
  if (!unit) throw new AppError('invalid_unit', 400)
  if (!Number.isFinite(draft.quantity) || draft.quantity < 0) throw new AppError('invalid_request', 400)
  const minimum = draft.minimumQuantity
  if (minimum !== null && (!Number.isFinite(minimum) || minimum < 0)) throw new AppError('invalid_request', 400)
  const date = normalizeDatePair(draft.dateType, draft.dateValue)
  return {
    ...(draft.id ? { id: draft.id.toLowerCase() } : {}),
    ingredientId: ingredient.id,
    displayName: draft.displayName.trim() || ingredient.displayName,
    quantity: roundPantryQuantity(draft.quantity),
    unit,
    location: draft.location,
    minimumQuantity: minimum === null ? null : roundPantryQuantity(minimum),
    ...date,
  }
}

function normalizePatch(current: PantryItem, patch: PantryPatch, resolve: Resolve): PantryPatch {
  const next: PantryPatch = { ...patch }
  if (patch.ingredientId !== undefined) {
    const ingredient = resolve(patch.ingredientId)
    if (!ingredient) throw new AppError('unknown_ingredient', 400)
    next.ingredientId = ingredient.id
  }
  if (patch.displayName !== undefined) {
    next.displayName = patch.displayName.trim()
    if (!next.displayName) throw new AppError('invalid_request', 400)
  }
  if (patch.unit !== undefined) {
    const unit = canonicalUnit(patch.unit)
    if (!unit) throw new AppError('invalid_unit', 400)
    next.unit = unit
    if (unitsCompatible(current.unit, unit)) {
      if (patch.quantity === undefined && current.unit !== unit) {
        next.quantity = convertPantryQuantity(current.quantity, current.unit, unit) ?? undefined
      }
      if (patch.minimumQuantity === undefined && current.minimumQuantity !== null && current.unit !== unit) {
        next.minimumQuantity = convertPantryQuantity(current.minimumQuantity, current.unit, unit)
      }
    } else if (patch.minimumQuantity === undefined && current.minimumQuantity !== null) {
      // A minimum written in the old unit would mean something else in the new one.
      throw new AppError('invalid_request', 400)
    }
  }
  if (next.quantity !== undefined && (!Number.isFinite(next.quantity) || next.quantity < 0)) throw new AppError('invalid_request', 400)
  if (next.minimumQuantity !== undefined && next.minimumQuantity !== null && (!Number.isFinite(next.minimumQuantity) || next.minimumQuantity < 0)) {
    throw new AppError('invalid_request', 400)
  }
  if (patch.dateType !== undefined || patch.dateValue !== undefined) {
    const date = normalizeDatePair(
      patch.dateType !== undefined ? patch.dateType : current.dateType,
      patch.dateValue !== undefined ? patch.dateValue : current.dateValue,
    )
    next.dateType = date.dateType
    next.dateValue = date.dateValue
  }
  if (next.quantity !== undefined) next.quantity = roundPantryQuantity(next.quantity)
  if (typeof next.minimumQuantity === 'number') next.minimumQuantity = roundPantryQuantity(next.minimumQuantity)
  return next
}

function mergeMinimum(existing: PantryItem, incoming: PantryCreateInput): number | null {
  if (incoming.minimumQuantity === null) return existing.minimumQuantity
  return convertPantryQuantity(incoming.minimumQuantity, incoming.unit, existing.unit)
}

/** Both fields or neither. The server never fills in a date the user did not enter. */
function normalizeDatePair(type: PantryDateType | null | undefined, value: string | null | undefined): { dateType: PantryDateType | null; dateValue: string | null } {
  const hasType = type !== null && type !== undefined
  const hasValue = value !== null && value !== undefined && value !== ''
  if (!hasType && !hasValue) return { dateType: null, dateValue: null }
  if (!hasType || !hasValue) throw new AppError('invalid_date', 400)
  if (type !== 'bestBefore' && type !== 'useBy') throw new AppError('invalid_date', 400)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new AppError('invalid_date', 400)
  const date = new Date(`${value}T00:00:00.000Z`)
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) throw new AppError('invalid_date', 400)
  return { dateType: type, dateValue: value }
}

async function authorize(households: HouseholdStore, householdId: string, accountId: string): Promise<void> {
  await households.transaction(async (tx) => {
    const household = await tx.household(householdId)
    if (!household || household.deletedAt) throw new AppError('not_found', 404)
    const members = await tx.members(householdId)
    if (!members.some((member) => member.accountId === accountId)) throw new AppError('forbidden', 403)
  })
}

async function idempotent<T>(store: PantryStore, accountId: string, householdId: string, key: string, body: unknown, now: Date, work: () => Promise<T>): Promise<T> {
  if (!key || key.length < 8 || key.length > 200) throw new AppError('invalid_request', 400)
  const requestHash = createHash('sha256').update(stable({ householdId, body })).digest('hex')
  const existing = await store.readPantryIdempotency(accountId, key)
  if (existing && existing.expiresAt.getTime() > now.getTime()) {
    if (existing.requestHash !== requestHash) throw new AppError('idempotency_key_reused', 409)
    return existing.responseBody as T
  }
  const result = await work()
  await store.writePantryIdempotency({
    accountId,
    key,
    householdId,
    requestHash,
    responseBody: result,
    expiresAt: new Date(now.getTime() + IDEMPOTENCY_MS),
  })
  return result
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>).filter(([, item]) => item !== undefined).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(',')}}`
  }
  return JSON.stringify(value) ?? 'null'
}
