import type { Pool, PoolClient } from 'pg'
import { AppError } from './errors.js'
import { makeIngredient, type Ingredient } from './ingredients.js'
import { pantryTimestamp, type PantryDraft, type PantryItem, type PantryPatch, type PantryStore } from './pantryTypes.js'
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
  date_type: PantryItem['dateType']
  date_value: string | Date | null
  version: number
  created_at: string | Date
  updated_at: string | Date
}

type IngredientDbRow = {
  id: string
  household_id: string | null
  display_name: string
  synonyms: string[]
  source_ids: string[]
  names: Record<string, string> | null
  aliases: Record<string, string[]> | null
}

const ingredientColumns = `i.id, i.household_id, i.display_name, i.synonyms, i.source_ids,
  (SELECT jsonb_object_agg(n.locale, n.display_name) FROM ingredient_names n WHERE n.ingredient_id = i.id) AS names,
  (SELECT jsonb_object_agg(a.locale, a.list) FROM (
     SELECT locale, jsonb_agg(alias ORDER BY position, alias) AS list
       FROM ingredient_aliases WHERE ingredient_id = i.id GROUP BY locale) a) AS aliases`

const columns = `id, household_id, ingredient_id, display_name, quantity, unit, location,
  minimum_quantity, date_type, to_char(date_value, 'YYYY-MM-DD') AS date_value, version, created_at, updated_at`

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
    dateType: row.date_type,
    dateValue: row.date_value === null ? null : String(row.date_value),
    version: row.version,
    createdAt: pantryTimestamp(new Date(row.created_at)),
    updatedAt: pantryTimestamp(new Date(row.updated_at)),
  }
}

function ingredientFromRow(row: IngredientDbRow): Ingredient {
  const names = row.names && Object.keys(row.names).length > 0 ? row.names : { 'tr-TR': row.display_name }
  const aliases = row.aliases ?? (row.names ? {} : { 'tr-TR': row.synonyms ?? [] })
  return makeIngredient({ id: row.id, householdId: row.household_id, names, aliases, sourceIds: row.source_ids ?? [] })
}

type Queryable = Pool | PoolClient

async function insertRow(db: Queryable, householdId: string, draft: PantryDraft, now: Date): Promise<PantryItem> {
  const result = await db.query<PantryDbRow>(
    `INSERT INTO pantry_items
       (id, household_id, ingredient_id, display_name, quantity, unit, location,
        minimum_quantity, date_type, date_value, version, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 1, $11, $11)
     RETURNING ${columns}`,
    [draft.id, householdId, draft.ingredientId, draft.displayName, draft.quantity, draft.unit, draft.location, draft.minimumQuantity, draft.dateType, draft.dateValue, now],
  )
  return fromRow(result.rows[0]!)
}

async function getRow(db: Queryable, householdId: string, itemId: string): Promise<PantryItem | null> {
  const result = await db.query<PantryDbRow>(`SELECT ${columns} FROM pantry_items WHERE household_id = $1 AND id = $2`, [householdId, itemId])
  return result.rows[0] ? fromRow(result.rows[0]) : null
}

async function updateRow(db: Queryable, current: PantryItem, patch: PantryPatch, now: Date): Promise<PantryItem | null> {
  const next = { ...current, ...patch }
  if (next.quantity < 0 || (next.minimumQuantity !== null && next.minimumQuantity < 0)) throw new AppError('invalid_request', 400)
  const result = await db.query<PantryDbRow>(
    `UPDATE pantry_items
        SET ingredient_id = $3, display_name = $4, quantity = $5, unit = $6,
            location = $7, minimum_quantity = $8, date_type = $9, date_value = $10,
            version = version + 1, updated_at = $11
      WHERE household_id = $1 AND id = $2 AND version = $12
    RETURNING ${columns}`,
    [current.householdId, current.id, next.ingredientId, next.displayName, next.quantity, next.unit, next.location, next.minimumQuantity, next.dateType, next.dateValue, now, current.version],
  )
  return result.rows[0] ? fromRow(result.rows[0]) : null
}

function translate(error: unknown): never {
  if (error instanceof AppError) throw error
  if (isCode(error, '23505')) throw new AppError('pantry_duplicate', 409)
  if (isCode(error, '23503')) throw new AppError('unknown_ingredient', 400)
  if (isCode(error, '23514')) throw new AppError('invalid_request', 400)
  throw error
}

export function createPgPantry(pool: Pool): PantryStore {
  return {
    async listPantry(householdId) {
      const result = await pool.query<PantryDbRow>(`SELECT ${columns} FROM pantry_items WHERE household_id = $1 ORDER BY updated_at, id`, [householdId])
      return result.rows.map(fromRow)
    },
    async getPantryItem(householdId, itemId) {
      return getRow(pool, householdId, itemId)
    },
    async insertPantryItem(householdId, draft, now) {
      try {
        return await insertRow(pool, householdId, draft, now)
      } catch (error) {
        translate(error)
      }
    },
    async updatePantryItem(householdId, itemId, patch, baseVersion, now) {
      const current = await getRow(pool, householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      if (baseVersion !== undefined && baseVersion !== current.version) throw new AppError('conflict', 409, undefined, { current })
      try {
        const updated = await updateRow(pool, current, patch, now)
        if (!updated) throw new AppError('conflict', 409, undefined, { current: await getRow(pool, householdId, itemId) })
        return updated
      } catch (error) {
        translate(error)
      }
    },
    async deletePantryItem(householdId, itemId, baseVersion) {
      const current = await getRow(pool, householdId, itemId)
      if (!current) throw new AppError('not_found', 404)
      if (baseVersion !== undefined && baseVersion !== current.version) throw new AppError('conflict', 409, undefined, { current })
      const result = await pool.query('DELETE FROM pantry_items WHERE household_id = $1 AND id = $2 AND version = $3', [householdId, itemId, current.version])
      if ((result.rowCount ?? 0) === 0) throw new AppError('conflict', 409, undefined, { current: await getRow(pool, householdId, itemId) })
    },
    async applyPantryBatch(householdId, batch, now) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        for (const update of batch.updates) {
          const current = await getRow(client, householdId, update.id)
          if (!current || current.version !== update.baseVersion) throw new AppError('conflict', 409, undefined, { current })
          if (!(await updateRow(client, current, update.patch, now))) throw new AppError('conflict', 409)
        }
        for (const draft of batch.inserts) await insertRow(client, householdId, draft, now)
        await client.query('COMMIT')
      } catch (error) {
        await client.query('ROLLBACK')
        translate(error)
      } finally {
        client.release()
      }
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
      await pool.query('DELETE FROM pantry_idempotency WHERE account_id = $1 AND expires_at <= now()', [row.accountId])
      await pool.query(
        `INSERT INTO pantry_idempotency (account_id, idempotency_key, household_id, request_hash, response_body, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (account_id, idempotency_key) DO UPDATE SET household_id = EXCLUDED.household_id,
           request_hash = EXCLUDED.request_hash, response_body = EXCLUDED.response_body, expires_at = EXCLUDED.expires_at`,
        [row.accountId, row.key, row.householdId, row.requestHash, JSON.stringify(row.responseBody), row.expiresAt],
      )
    },
    async clearAccountPantry(accountId) {
      await pool.query('DELETE FROM pantry_idempotency WHERE account_id = $1', [accountId])
    },
    async deleteHouseholdPantry(householdId) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        await client.query('DELETE FROM pantry_items WHERE household_id = $1', [householdId])
        await client.query('DELETE FROM ingredients WHERE household_id = $1', [householdId])
        await client.query('DELETE FROM pantry_idempotency WHERE household_id = $1', [householdId])
        await client.query('COMMIT')
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      } finally {
        client.release()
      }
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
    async listIngredients(householdId) {
      const result = householdId
        ? await pool.query<IngredientDbRow>(`SELECT ${ingredientColumns} FROM ingredients i WHERE i.household_id = $1 ORDER BY i.created_at, i.id`, [householdId])
        : await pool.query<IngredientDbRow>(`SELECT ${ingredientColumns} FROM ingredients i WHERE i.household_id IS NULL ORDER BY i.id`)
      return result.rows.map(ingredientFromRow)
    },
    async getIngredient(id) {
      const result = await pool.query<IngredientDbRow>(`SELECT ${ingredientColumns} FROM ingredients i WHERE i.id = $1`, [id])
      return result.rows[0] ? ingredientFromRow(result.rows[0]) : null
    },
    async insertIngredient(ingredient, now) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        await client.query(
          `INSERT INTO ingredients (id, household_id, display_name, synonyms, source_ids, created_at)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [ingredient.id, ingredient.householdId, ingredient.displayName, ingredient.synonyms, ingredient.sourceIds, now],
        )
        for (const [locale, name] of Object.entries(ingredient.names)) {
          await client.query('INSERT INTO ingredient_names (ingredient_id, locale, display_name) VALUES ($1, $2, $3)', [ingredient.id, locale, name])
        }
        for (const [locale, list] of Object.entries(ingredient.aliases)) {
          for (const [position, alias] of list.entries()) {
            await client.query(
              'INSERT INTO ingredient_aliases (ingredient_id, locale, alias, position) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
              [ingredient.id, locale, alias, position + 1],
            )
          }
        }
        const result = await client.query<IngredientDbRow>(`SELECT ${ingredientColumns} FROM ingredients i WHERE i.id = $1`, [ingredient.id])
        await client.query('COMMIT')
        return ingredientFromRow(result.rows[0]!)
      } catch (error) {
        await client.query('ROLLBACK')
        if (isCode(error, '23505')) throw new AppError('ingredient_conflict', 409)
        throw error
      } finally {
        client.release()
      }
    },
  }
}

function isCode(error: unknown, code: string): boolean {
  return Boolean(error && typeof error === 'object' && 'code' in error && (error as { code?: string }).code === code)
}
