import type { MemberRole } from './repository.js'

export type PantryLocation = 'pantry' | 'refrigerator' | 'freezer' | 'other'

export interface PantryItem {
  id: string
  householdId: string
  ingredientId: string
  displayName: string
  quantity: number
  unit: string
  location: PantryLocation
  minimumQuantity: number | null
  bestBefore: string | null
  revision: number
  createdAt: string
  updatedAt: string
}

export interface PantryDraft {
  id: string
  ingredientId: string
  displayName: string
  quantity: number
  unit: string
  location: PantryLocation
  minimumQuantity: number | null
  bestBefore: string | null
}

export interface PantryPatch {
  ingredientId?: string
  displayName?: string
  quantity?: number
  unit?: string
  location?: PantryLocation
  minimumQuantity?: number | null
  bestBefore?: string | null
}

export interface PantryIdempotencyHit {
  requestHash: string
  responseBody: unknown
  expiresAt: Date
}

export interface PantryStore {
  listPantry(householdId: string): Promise<PantryItem[]>
  getPantryItem(householdId: string, itemId: string): Promise<PantryItem | null>
  insertPantryItem(householdId: string, draft: PantryDraft, now: Date): Promise<PantryItem>
  updatePantryItem(householdId: string, itemId: string, patch: PantryPatch, baseRevision: number | undefined, now: Date): Promise<PantryItem>
  deletePantryItem(householdId: string, itemId: string, baseRevision: number | undefined): Promise<void>
  readPantryIdempotency(accountId: string, key: string): Promise<PantryIdempotencyHit | null>
  writePantryIdempotency(row: PantryIdempotencyHit & { accountId: string; key: string }): Promise<void>
  clearAccountPantry(accountId: string): Promise<void>
  householdForPantryItem(itemId: string): Promise<string | null>
  householdMembers(householdId: string): Promise<{ accountId: string; role: MemberRole }[]>
}
