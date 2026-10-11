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
  PantryLocation,
  PantryPatch,
  PantryReconcileLine,
  PantryReconcileOperation,
  PantryReconcileResultLine,
  PantrySiblingPatch,
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
          const samePlace = rows.find((item) => item.ingredientId === normalized.ingredientId && item.location === normalized.location && unitsCompatible(item.unit, normalized.unit))
          if (samePlace) {
            const added = convertPantryQuantity(normalized.quantity, normalized.unit, samePlace.unit)
            if (added === null) throw new AppError('invalid_unit', 400)
            // A merge is still a create: the group minimum can only rise, and auto-add stays on if any sibling has it.
            const settings = effectiveCreateSettings(
              rows.filter((item) => item.ingredientId === normalized.ingredientId && unitsCompatible(item.unit, normalized.unit)),
              normalized,
            )
            const minimumQuantity = settings.minimumQuantity === null ? null : convertPantryQuantity(settings.minimumQuantity, normalized.unit, samePlace.unit)
            if (settings.minimumQuantity !== null && minimumQuantity === null) throw new AppError('invalid_unit', 400)
            const date = mergedDate(samePlace.dateType, samePlace.dateValue, normalized.dateType, normalized.dateValue)
            return store.updatePantryItem(householdId, samePlace.id, {
              quantity: roundPantryQuantity(samePlace.quantity + added),
              displayName: normalized.displayName,
              minimumQuantity,
              autoAddToGrocery: settings.autoAddToGrocery,
              dateType: date.dateType,
              dateValue: date.dateValue,
            }, samePlace.version, now, siblingPatches(rows, samePlace.ingredientId, samePlace.unit, { minimumQuantity, autoAddToGrocery: settings.autoAddToGrocery }, new Set([samePlace.id])))
          }
          const blocked = rows.find((item) => item.ingredientId === normalized.ingredientId && !unitsCompatible(item.unit, normalized.unit))
          if (blocked && !confirmSeparate) {
            throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: blocked.unit, incomingUnit: normalized.unit, current: blocked })
          }
          const siblings = rows.filter((item) => item.ingredientId === normalized.ingredientId && unitsCompatible(item.unit, normalized.unit))
          const settings = effectiveCreateSettings(siblings, normalized)
          const id = normalized.id ?? randomUUID()
          const draft = { ...normalized, id, minimumQuantity: settings.minimumQuantity, autoAddToGrocery: settings.autoAddToGrocery }
          const copies = siblingPatches(siblings, draft.ingredientId, draft.unit, settings, new Set())
          if (copies.length === 0) return store.insertPantryItem(householdId, draft, now)
          await store.applyPantryBatch(householdId, {
            inserts: [draft],
            updates: copies.map((copy) => {
              const current = siblings.find((item) => item.id === copy.id)
              return { id: copy.id, baseVersion: current?.version ?? 0, patch: copy.patch }
            }),
          }, now)
          const saved = await store.getPantryItem(householdId, id)
          if (!saved) throw new AppError('conflict', 409)
          return saved
        })
      }) as Promise<PantryItem>
    },
    async update(accountId, householdId, itemId, patch, baseVersion, key, now, options) {
      await authorize(households, householdId, accountId)
      const resolve = await resolver(householdId)
      const confirmSeparate = options?.confirmSeparate === true
      // Hash the client patch. A location merge deletes the source, and the replay
      // must still return the stored survivor before that missing row is a 404.
      return idempotent(store, accountId, householdId, key, { itemId, patch, baseVersion, confirmSeparate }, now, async () => {
        return withFreshState(async () => {
          const latest = await store.getPantryItem(householdId, itemId)
          if (!latest) throw new AppError('not_found', 404)
          const normalized = normalizePatch(latest, patch, resolve)
          if (baseVersion !== undefined && baseVersion !== latest.version) throw new AppError('conflict', 409, undefined, { current: latest })
          if (normalized.unit && !unitsCompatible(latest.unit, normalized.unit) && !confirmSeparate) {
            throw new AppError('pantry_unit_choice', 409, undefined, { existingUnit: latest.unit, incomingUnit: normalized.unit, current: latest })
          }
          const nextUnit = normalized.unit ?? latest.unit
          const nextLocation = normalized.location ?? latest.location
          const nextIngredient = normalized.ingredientId ?? latest.ingredientId
          const rows = await store.listPantry(householdId)
          const occupant = rows.find((item) => item.id !== latest.id && item.ingredientId === nextIngredient && item.location === nextLocation && unitsCompatible(item.unit, nextUnit))
          if (occupant) {
            const sourceQuantity = normalized.quantity ?? convertPantryQuantity(latest.quantity, latest.unit, nextUnit)
            const added = sourceQuantity === null ? null : convertPantryQuantity(sourceQuantity, nextUnit, occupant.unit)
            if (added === null) throw new AppError('invalid_unit', 400)
            const incomingType = normalized.dateType !== undefined ? normalized.dateType : latest.dateType
            const incomingValue = normalized.dateValue !== undefined ? normalized.dateValue : latest.dateValue
            const date = mergedDate(occupant.dateType, occupant.dateValue, incomingType, incomingValue)
            const minimumQuantity = normalized.minimumQuantity !== undefined
              ? (normalized.minimumQuantity === null ? null : convertPantryQuantity(normalized.minimumQuantity, nextUnit, occupant.unit))
              : occupant.minimumQuantity
            const autoAddToGrocery = normalized.autoAddToGrocery !== undefined ? normalized.autoAddToGrocery : occupant.autoAddToGrocery
            return store.mergePantryLocations(householdId, latest.id, latest.version, occupant.id, {
              quantity: roundPantryQuantity(occupant.quantity + added),
              displayName: normalized.displayName ?? latest.displayName,
              minimumQuantity,
              autoAddToGrocery,
              dateType: date.dateType,
              dateValue: date.dateValue,
            }, siblingPatches(rows, occupant.ingredientId, occupant.unit, { minimumQuantity, autoAddToGrocery }, new Set([latest.id, occupant.id])), now)
          }
          const settingPatch: { minimumQuantity?: number | null; autoAddToGrocery?: boolean } = {}
          if (minimumChanged(latest, normalized, nextUnit)) settingPatch.minimumQuantity = normalized.minimumQuantity
          if (normalized.autoAddToGrocery !== undefined && normalized.autoAddToGrocery !== latest.autoAddToGrocery) {
            settingPatch.autoAddToGrocery = normalized.autoAddToGrocery
          }
          return store.updatePantryItem(householdId, itemId, normalized, latest.version, now, siblingPatches(rows, nextIngredient, nextUnit, settingPatch, new Set([latest.id])))
        })
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
      // `pantry_duplicate` is the unique-key race after 0015. The next read merges into the row that won.
      const retryable = error instanceof AppError && (error.code === 'conflict' || error.code === 'pantry_duplicate')
      if (attempt >= STALE_RETRIES || !retryable) throw error
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
  const compatible = sameIngredient.filter((item) => unitsCompatible(item.unit, unit)).sort(byPlace)
  if (compatible.length === 0) {
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
        autoAddToGrocery: false,
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
  if (operation === 'compute-missing') {
    const available = stockInUnit(compatible, unit)
    const remaining = roundPantryQuantity(Math.max(0, line.quantity - available))
    deduct(compatible, roundPantryQuantity(line.quantity - remaining), unit)
    return { ...base, quantity: remaining, applied: true }
  }
  if (operation === 'consume') {
    deduct(compatible, line.quantity, unit)
    return { ...base, applied: true }
  }
  const target = (line.location ? compatible.find((item) => item.location === line.location) : undefined) ?? compatible[0]
  if (!target) return { ...base, incompatible: true }
  const converted = convertPantryQuantity(line.quantity, unit, target.unit)
  if (converted === null) return { ...base, incompatible: true }
  target.quantity = roundPantryQuantity(target.quantity + converted)
  return { ...base, applied: true }
}

/** Earliest calendar day, undated last, then kiler / buzdolabı / dondurucu / diğer, then id. */
function byPlace(a: PantryItem, b: PantryItem): number {
  const aDay = a.dateValue ?? '9999-99-99'
  const bDay = b.dateValue ?? '9999-99-99'
  if (aDay !== bDay) return aDay < bDay ? -1 : 1
  const rank = placeRank(a.location) - placeRank(b.location)
  if (rank !== 0) return rank
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
}

function placeRank(location: PantryLocation): number {
  switch (location) {
    case 'pantry': return 0
    case 'refrigerator': return 1
    case 'freezer': return 2
    default: return 3
  }
}

function stockInUnit(rows: PantryItem[], unit: string): number {
  return roundPantryQuantity(rows.reduce((sum, row) => sum + (convertPantryQuantity(row.quantity, row.unit, unit) ?? 0), 0))
}

function deduct(rows: PantryItem[], amount: number, unit: string): void {
  let left = roundPantryQuantity(Math.max(0, amount))
  for (const row of rows) {
    if (left <= 0) break
    const have = convertPantryQuantity(row.quantity, row.unit, unit) ?? 0
    const take = Math.min(have, left)
    const taken = convertPantryQuantity(take, unit, row.unit) ?? 0
    row.quantity = roundPantryQuantity(Math.max(0, row.quantity - taken))
    left = roundPantryQuantity(Math.max(0, left - take))
  }
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
        autoAddToGrocery: false,
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
    autoAddToGrocery: draft.autoAddToGrocery === true,
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
  if (patch.autoAddToGrocery !== undefined && typeof patch.autoAddToGrocery !== 'boolean') {
    throw new AppError('invalid_request', 400)
  }
  return next
}

/**
 * Date rule when two rows become one. The target is the row that already
 * occupies the destination (on create, the same-place row).
 * Both undated stays undated. One dated side keeps that pair.
 * The same date type keeps the earlier `YYYY-MM-DD`.
 * `bestBefore` and `useBy` are not converted: the target's type and day stay,
 * and the other type is dropped. Quantity still merges.
 */
function mergedDate(
  keptType: PantryDateType | null,
  keptValue: string | null,
  incomingType: PantryDateType | null,
  incomingValue: string | null,
): { dateType: PantryDateType | null; dateValue: string | null } {
  if (!keptType || !keptValue) {
    if (incomingType && incomingValue) return { dateType: incomingType, dateValue: incomingValue }
    return { dateType: null, dateValue: null }
  }
  if (!incomingType || !incomingValue) return { dateType: keptType, dateValue: keptValue }
  if (keptType !== incomingType) return { dateType: keptType, dateValue: keptValue }
  if (incomingValue < keptValue) return { dateType: incomingType, dateValue: incomingValue }
  return { dateType: keptType, dateValue: keptValue }
}

/** Create never lowers the group minimum and never turns auto-add off. */
function effectiveCreateSettings(siblings: PantryItem[], incoming: PantryCreateInput): { minimumQuantity: number | null; autoAddToGrocery: boolean } {
  let minimum = incoming.minimumQuantity
  let autoAddToGrocery = incoming.autoAddToGrocery
  for (const row of siblings) {
    autoAddToGrocery = autoAddToGrocery || row.autoAddToGrocery
    if (row.minimumQuantity === null) continue
    const converted = convertPantryQuantity(row.minimumQuantity, row.unit, incoming.unit)
    if (converted === null) continue
    minimum = minimum === null ? converted : roundPantryQuantity(Math.max(minimum, converted))
  }
  return { minimumQuantity: minimum === null ? null : roundPantryQuantity(minimum), autoAddToGrocery }
}

function sameQuantity(left: number | null | undefined, right: number | null | undefined): boolean {
  if (left == null && right == null) return true
  if (left == null || right == null) return false
  return roundPantryQuantity(left) === roundPantryQuantity(right)
}

function minimumChanged(latest: PantryItem, patch: PantryPatch, nextUnit: string): boolean {
  if (patch.minimumQuantity === undefined) return false
  const previous = latest.minimumQuantity === null ? null : convertPantryQuantity(latest.minimumQuantity, latest.unit, nextUnit)
  return !sameQuantity(previous, patch.minimumQuantity)
}

function siblingPatches(
  rows: PantryItem[],
  ingredientId: string,
  unit: string,
  settings: { minimumQuantity?: number | null; autoAddToGrocery?: boolean },
  except: Set<string>,
): PantrySiblingPatch[] {
  const patches: PantrySiblingPatch[] = []
  for (const row of rows) {
    if (except.has(row.id)) continue
    if (row.ingredientId !== ingredientId || !unitsCompatible(row.unit, unit)) continue
    const patch: PantryPatch = {}
    if (settings.minimumQuantity !== undefined) {
      const minimumQuantity = settings.minimumQuantity === null ? null : convertPantryQuantity(settings.minimumQuantity, unit, row.unit)
      if (settings.minimumQuantity !== null && minimumQuantity === null) continue
      if (!sameQuantity(row.minimumQuantity, minimumQuantity)) patch.minimumQuantity = minimumQuantity
    }
    if (settings.autoAddToGrocery !== undefined && row.autoAddToGrocery !== settings.autoAddToGrocery) {
      patch.autoAddToGrocery = settings.autoAddToGrocery
    }
    if (patch.minimumQuantity !== undefined || patch.autoAddToGrocery !== undefined) patches.push({ id: row.id, patch })
  }
  return patches
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
