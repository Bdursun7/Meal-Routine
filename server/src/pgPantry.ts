import type { Pool } from 'pg'
import { AppError } from './errors.js'
import type { PantryDraft, PantryIdempotencyHit, PantryItem, PantryPatch, PantryStore } from './pantryTypes.js'
import type { MemberRole } from './repository.js'

type PantryDbRow = {
  id: string
  household_id: string
  ingredient_id: string
  display_name: string
  quantity: string | number
  unit: string
  location: PantryItem['location']
  minimum_quantity: string | number | null
  best_before: string | Date | null
  revision: number
  created_at: string | Date
  updated_at: string | Date
}

function fromRow(row: PantryDbRow): PantryItem {
  return {
    id: row.id,
    householdId: row.household_id,
    ingredientId: row.ingredient_id,
    displayName: row.display_name,
    quantity: Number(row.quantity),
    unit: row.unit,
    location: row.location,
    minimumQuantity: row.minimum_quantity === null ? null : Number(row.minimum_quantity),
    bestBefore: row.best_before ? new Date(row.best_before).toISOString().slice(0, 10) : null,
    revision: row.revision,
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString(),
  }
}

export function createPgPantry(pool: Pool): PantryStore {
  return {
    async listPantry(householdId) {
      const result = await pool.query<PantryDbRow>(
        `SELECT id, household_id, ingredient_id, display_name, quantity, unit, location,
                minimum_quantity, best_before, revision, created_at, updated_at
           FROM pantry_items WHERE household_id = $1 ORDER BY updated_at, id`,
        [householdId],
      )
      return result.rows.map(fromRow)
    },
    async getPantryItem(householdId, itemId) {
      const result = await pool.query<PantryDbRow>(
        `SELECT id, household_id, ingredient_id, display_name, quantity, unit, location,
                minimum_quantity, best_before, revision, created_at, updated_at
           FROM pantry_items WHERE household_id = $1 AND id = $2`,
        [householdId, itemId],
      )
      return result.rows[0] ? fromRow(result.rows[0]) : null
    },
    async insertPantryItem(householdId, draft, now) {
      try {
        const result = await pool.query<PantryDbRow>(
          `INSERT INTO pantry_items
             (id, household_id, ingredient_id, display_name, quantity, unit, location,
              minimum_quantity, best_before, revision, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 1, $10, $10)
           RETURNING id, household_id, ingredient_id, display_name, quantity, unit, location,
                     minimum_quantity, best_before, revision, created_at, updated_at`,
          [draft.id, householdId, draft.ingredientId, draft.displayName, draft.quantity, draft.unit, draft.location, draft.minimumQuantity, draft.bestBefore, now],
        )
        return fromRow(result.rows[0]!)
      } catch (error) {
        if (isCode(error, '23505')) throw new AppError('pantry_duplicate', 409)
        throw error
      }
    },
    async updatePantryItem(householdId, itemId, patch, baseRevision, now) {
      const current = await this.getPantryItem(householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      if (baseRevision !== undefined && baseRevision !== current.revision) throw new AppError('conflict', 409, undefined, { current })
      const next = { ...current, ...patch }
      if (next.quantity < 0 || (next.minimumQuantity !== null && next.minimumQuantity < 0)) throw new AppError('invalid_request', 400)
      try {
        const result = await pool.query<PantryDbRow>(
          `UPDATE pantry_items
              SET ingredient_id = $3, display_name = $4, quantity = $5, unit = $6,
                  location = $7, minimum_quantity = $8, best_before = $9,
                  revision = revision + 1, updated_at = $10
            WHERE household_id = $1 AND id = $2 AND revision = $11
          RETURNING id, household_id, ingredient_id, display_name, quantity, unit, location,
                    minimum_quantity, best_before, revision, created_at, updated_at`,
          [householdId, itemId, next.ingredientId, next.displayName, next.quantity, next.unit, next.location, next.minimumQuantity, next.bestBefore, now, current.revision],
        )
        if (!result.rows[0]) throw new AppError('conflict', 409, undefined, { current: await this.getPantryItem(householdId, itemId) })
        return fromRow(result.rows[0])
      } catch (error) {
        if (error instanceof AppError) throw error
        if (isCode(error, '23505')) throw new AppError('pantry_duplicate', 409)
        throw error
      }
    },
    async deletePantryItem(householdId, itemId, baseRevision) {
      const current = await this.getPantryItem(householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      if (baseRevision !== undefined && baseRevision !== current.revision) throw new AppError('conflict', 409, undefined, { current })
      const result = await pool.query('DELETE FROM pantry_items WHERE household_id = $1 AND id = $2 AND revision = $3', [householdId, itemId, current.revision])
      if ((result.rowCount ?? 0) === 0) throw new AppError('conflict', 409)
    },
    async readPantryIdempotency(accountId, key) {
      const result = await pool.query<{ request_hash: string; response_body: unknown; expires_at: Date }>(
        `SELECT request_hash, response_body, expires_at FROM pantry_idempotency WHERE account_id = $1 AND idempotency_key = $2`,
        [accountId, key],
      )
      const row = result.rows[0]
      return row ? { requestHash: row.request_hash, responseBody: row.response_body, expiresAt: new Date(row.expires_at) } : null
    },
    async writePantryIdempotency(row) {
      await pool.query(
        `INSERT INTO pantry_idempotency (account_id, idempotency_key, request_hash, response_body, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (account_id, idempotency_key) DO UPDATE SET request_hash = EXCLUDED.request_hash,
           response_body = EXCLUDED.response_body, expires_at = EXCLUDED.expires_at`,
        [row.accountId, row.key, row.requestHash, row.responseBody, row.expiresAt],
      )
    },
    async clearAccountPantry(accountId) {
      await pool.query('DELETE FROM pantry_idempotency WHERE account_id = $1', [accountId])
    },
    async householdForPantryItem(itemId) {
      const result = await pool.query<{ household_id: string }>('SELECT household_id FROM pantry_items WHERE id = $1', [itemId])
      return result.rows[0]?.household_id ?? null
    },
    async householdMembers(householdId) {
      const result = await pool.query<{ account_id: string; role: MemberRole }>(
        `SELECT account_id, role FROM household_members WHERE household_id = $1 AND left_at IS NULL`,
        [householdId],
      )
      return result.rows.map((row) => ({ accountId: row.account_id, role: row.role }))
    },
  }
}

function isCode(error: unknown, code: string): boolean {
  return Boolean(error && typeof error === 'object' && 'code' in error && (error as { code?: string }).code === code)
}
