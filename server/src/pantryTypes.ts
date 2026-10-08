import type { Ingredient } from './ingredients.js'
import type { MemberRole } from './repository.js'

export type PantryLocation = 'pantry' | 'refrigerator' | 'freezer' | 'other'

/** `useBy` is the real last safe day; `bestBefore` is quality. The server never derives one. */
export type PantryDateType = 'bestBefore' | 'useBy'

export interface PantryItem {
  id: string
  householdId: string
  ingredientId: string
  displayName: string
  quantity: number
  unit: string
  location: PantryLocation
  minimumQuantity: number | null
  dateType: PantryDateType | null
  dateValue: string | null
  version: number
  createdAt: string
  updatedAt: string
}

/**
 * Pantry wire clock. Node `Date.toISOString()`: an ISO-8601 UTC string with
 * millisecond precision (`2026-10-08T07:12:03.123Z`), including `.000`.
 * Never a numeric epoch. The iOS decoder accepts this form, the same instant
 * without a fraction, and epoch milliseconds if an older payload carries one.
 */
export function pantryTimestamp(date: Date): string {
  return date.toISOString()
}

export interface PantryDraft {
  id: string
  ingredientId: string
  displayName: string
  quantity: number
  unit: string
  location: PantryLocation
  minimumQuantity: number | null
  dateType: PantryDateType | null
  dateValue: string | null
}

export interface PantryPatch {
  ingredientId?: string
  displayName?: string
  quantity?: number
  unit?: string
  location?: PantryLocation
  minimumQuantity?: number | null
  dateType?: PantryDateType | null
  dateValue?: string | null
}

export interface PantryIdempotencyHit {
  requestHash: string
  responseBody: unknown
  expiresAt: Date
}

export type PantryReconcileOperation = 'compute-missing' | 'consume' | 'restock'

export interface PantryReconcileLine {
  ingredientId: string
  displayName?: string
  quantity: number
  unit: string
  checked?: boolean
  location?: PantryLocation
}

export interface PantryReconcileResultLine {
  ingredientId: string
  /** Dictionary id the line matched. Null when the id is not in the dictionary. */
  resolvedIngredientId: string | null
  displayName: string
  quantity: number
  unit: string
  checked: boolean
  incompatible: boolean
  unknownIngredient: boolean
  applied: boolean
}

export interface PantryBatch {
  inserts: PantryDraft[]
  updates: { id: string; baseVersion: number; patch: PantryPatch }[]
}

export interface PantryStore {
  listPantry(householdId: string): Promise<PantryItem[]>
  getPantryItem(householdId: string, itemId: string): Promise<PantryItem | null>
  insertPantryItem(householdId: string, draft: PantryDraft, now: Date): Promise<PantryItem>
  updatePantryItem(householdId: string, itemId: string, patch: PantryPatch, baseVersion: number | undefined, now: Date): Promise<PantryItem>
  deletePantryItem(householdId: string, itemId: string, baseVersion: number | undefined): Promise<void>
  readPantryIdempotency(accountId: string, key: string): Promise<PantryIdempotencyHit | null>
  writePantryIdempotency(row: PantryIdempotencyHit & { accountId: string; key: string; householdId: string | null }): Promise<void>
  clearAccountPantry(accountId: string): Promise<void>
  /** Items, household-created ingredients and replay rows for the household. */
  deleteHouseholdPantry(householdId: string): Promise<void>
  householdForPantryItem(itemId: string): Promise<string | null>
  householdMembers(householdId: string): Promise<{ accountId: string; role: MemberRole }[]>
  /** All-or-nothing. A row whose version moved fails the whole batch with `conflict`. */
  applyPantryBatch(householdId: string, batch: PantryBatch, now: Date): Promise<void>
  /** Null: the seed dictionary. A household id: only that household's `custom:` ingredients. */
  listIngredients(householdId: string | null): Promise<Ingredient[]>
  getIngredient(id: string): Promise<Ingredient | null>
  insertIngredient(ingredient: Ingredient, now: Date): Promise<Ingredient>
}
