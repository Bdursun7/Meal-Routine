import type { Pool, PoolClient } from 'pg'
import type {
  BoardDocument,
  BoardStore,
  BoardTx,
  GroceryRow,
  MealRow,
  PlanRow,
  ReactionRow,
} from './boardTypes.js'
import { ACTIVITY_DETAIL_CODES, defaultPreference, type ActivityDetailCode } from './boardTypes.js'

function activityDetailCode(raw: string | null): ActivityDetailCode | null {
  return (ACTIVITY_DETAIL_CODES as readonly string[]).includes(raw ?? '') ? (raw as ActivityDetailCode) : null
}

export function createPgBoard(pool: Pool): BoardStore {
  return {
    async boardTransaction(work) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        const result = await work(pgBoardTx(client))
        await client.query('COMMIT')
        return result
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      } finally {
        client.release()
      }
    },
  }
}

function pgBoardTx(client: PoolClient): BoardTx {
  return {
    async readIdempotency(accountId, key) {
      const result = await client.query<{
        request_hash: string
        response_status: number
        response_body: unknown
        expires_at: Date
      }>(
        `SELECT request_hash, response_status, response_body, expires_at
           FROM idempotency_keys
          WHERE account_id = $1 AND idempotency_key = $2`,
        [accountId, key],
      )
      const row = result.rows[0]
      if (!row) return null
      return {
        requestHash: row.request_hash,
        responseStatus: row.response_status,
        responseBody: row.response_body,
        expiresAt: new Date(row.expires_at),
      }
    },
    async writeIdempotency(row) {
      await client.query(
        `INSERT INTO idempotency_keys (
           account_id, idempotency_key, request_hash, response_status, response_body, created_at, expires_at
         ) VALUES ($1, $2, $3, $4, $5::jsonb, now(), $6)
         ON CONFLICT (account_id, idempotency_key) DO UPDATE
           SET request_hash = EXCLUDED.request_hash,
               response_status = EXCLUDED.response_status,
               response_body = EXCLUDED.response_body,
               expires_at = EXCLUDED.expires_at`,
        [row.accountId, row.key, row.requestHash, row.responseStatus, JSON.stringify(row.responseBody), row.expiresAt],
      )
    },
    async load(householdId) {
      return loadBoard(client, householdId)
    },
    async persist(householdId, document, changes) {
      await saveBoard(client, householdId, document)
      let cursor = document.cursor
      for (const change of changes) {
        const inserted = await client.query<{ cursor: string }>(
          `INSERT INTO sync_changes (household_id, entity_type, entity_id, operation_type, revision, payload)
           VALUES ($1, $2, $3, $4, $5, $6::jsonb)
           RETURNING cursor`,
          [householdId, change.entityType, change.entityId, change.operationType, change.revision, JSON.stringify(change.payload)],
        )
        cursor = Number(inserted.rows[0]?.cursor ?? cursor)
        await client.query(
          `INSERT INTO entity_versions (entity_type, entity_id, household_id, revision, updated_at)
           VALUES ($1, $2, $3, $4, now())
           ON CONFLICT (entity_type, entity_id) DO UPDATE
             SET revision = EXCLUDED.revision,
                 household_id = EXCLUDED.household_id,
                 updated_at = now()`,
          [change.entityType, change.entityId, householdId, change.revision],
        )
      }
      return cursor
    },
    async changesSince(householdId, cursor) {
      const latest = await client.query<{ cursor: string }>(
        'SELECT COALESCE(MAX(cursor), 0)::text AS cursor FROM sync_changes WHERE household_id = $1',
        [householdId],
      )
      const result = await client.query<{
        cursor: string
        entity_type: string
        entity_id: string
        operation_type: string
        revision: number
        payload: unknown
      }>(
        `SELECT cursor::text, entity_type, entity_id, operation_type, revision, payload
           FROM sync_changes
          WHERE household_id = $1 AND cursor > $2
          ORDER BY cursor`,
        [householdId, cursor],
      )
      return {
        cursor: Number(latest.rows[0]?.cursor ?? 0),
        changes: result.rows.map((row) => ({
          cursor: Number(row.cursor),
          entityType: row.entity_type,
          entityId: row.entity_id,
          operationType: row.operation_type,
          revision: row.revision,
          payload: row.payload,
        })),
      }
    },
  }
}

async function loadBoard(client: PoolClient, householdId: string): Promise<BoardDocument> {
  const preference = await client.query<{
    cooking_days: number[]
    max_weekday_minutes: number
    preferred_categories: string[]
    preferred_proteins: string[]
    avoided_ingredients: string[]
    revision: number
  }>(
    `SELECT cooking_days, max_weekday_minutes, preferred_categories, preferred_proteins, avoided_ingredients, revision
       FROM household_preferences WHERE household_id = $1`,
    [householdId],
  )
  const plans = await client.query<{
    id: string
    week_start: string
    status: PlanRow['status']
    is_finalized: boolean
    revision: number
  }>(
    `SELECT id, week_start::text, status, is_finalized, revision
       FROM shared_plans WHERE household_id = $1 ORDER BY week_start`,
    [householdId],
  )
  const meals = await client.query<{
    id: string
    plan_id: string
    day_offset: number
    recipe_slug: string
    title: string
    recipe_owner_account_id: string | null
    status: MealRow['status']
    revision: number
  }>(
    `SELECT m.id, m.plan_id, m.day_offset, m.recipe_slug, m.title, m.recipe_owner_account_id, m.status, m.revision
       FROM shared_meals m
       JOIN shared_plans p ON p.id = m.plan_id
      WHERE p.household_id = $1`,
    [householdId],
  )
  const reactions = await client.query<{
    id: string
    shared_meal_id: string
    account_id: string
    reaction: ReactionRow['reaction']
    revision: number
  }>(
    `SELECT r.id, r.shared_meal_id, r.account_id, r.reaction, r.revision
       FROM meal_reactions r
       JOIN shared_meals m ON m.id = r.shared_meal_id
       JOIN shared_plans p ON p.id = m.plan_id
      WHERE p.household_id = $1`,
    [householdId],
  )
  const grocery = await client.query<{
    id: string
    item_key: string
    quantity: number
    is_checked: boolean
    updated_by: string | null
    revision: number
  }>(
    `SELECT id, item_key, quantity, is_checked, updated_by, revision
       FROM shared_grocery_items WHERE household_id = $1 ORDER BY item_key`,
    [householdId],
  )
  const activity = await client.query<{
    id: string
    actor_account_id: string | null
    actor_name: string
    kind: string
    meal_title: string
    detail: string
    detail_code: string | null
    created_at: Date
  }>(
    `SELECT id, actor_account_id, actor_name, kind, meal_title, detail, detail_code, created_at
       FROM household_activity
      WHERE household_id = $1
      ORDER BY created_at DESC
      LIMIT 40`,
    [householdId],
  )
  const cursor = await client.query<{ cursor: string }>(
    'SELECT COALESCE(MAX(cursor), 0)::text AS cursor FROM sync_changes WHERE household_id = $1',
    [householdId],
  )
  const preferenceRow = preference.rows[0]
  const reactionsByMeal = new Map<string, ReactionRow[]>()
  for (const row of reactions.rows) {
    const list = reactionsByMeal.get(row.shared_meal_id) ?? []
    list.push({
      id: row.id,
      mealId: row.shared_meal_id,
      accountId: row.account_id,
      reaction: row.reaction,
      revision: row.revision,
    })
    reactionsByMeal.set(row.shared_meal_id, list)
  }
  const mealsByPlan = new Map<string, MealRow[]>()
  for (const row of meals.rows) {
    const list = mealsByPlan.get(row.plan_id) ?? []
    list.push({
      id: row.id,
      planId: row.plan_id,
      dayOffset: row.day_offset,
      recipeSlug: row.recipe_slug,
      title: row.title,
      recipeOwnerAccountId: row.recipe_owner_account_id,
      status: row.status,
      revision: row.revision,
      reactions: reactionsByMeal.get(row.id) ?? [],
    })
    mealsByPlan.set(row.plan_id, list)
  }
  return {
    cursor: Number(cursor.rows[0]?.cursor ?? 0),
    preference: preferenceRow
      ? {
          householdId,
          cookingDays: preferenceRow.cooking_days ?? [],
          maxWeekdayMinutes: preferenceRow.max_weekday_minutes,
          preferredCategories: preferenceRow.preferred_categories ?? [],
          preferredProteins: preferenceRow.preferred_proteins ?? [],
          avoidedIngredients: preferenceRow.avoided_ingredients ?? [],
          revision: preferenceRow.revision,
        }
      : defaultPreference(householdId),
    plans: plans.rows.map((plan) => ({
      id: plan.id,
      householdId,
      weekStart: String(plan.week_start).slice(0, 10),
      status: plan.status,
      isFinalized: plan.is_finalized,
      revision: plan.revision,
      meals: mealsByPlan.get(plan.id) ?? [],
    })),
    grocery: grocery.rows.map((row) => ({
      id: row.id,
      householdId,
      itemKey: row.item_key,
      quantity: row.quantity,
      isChecked: row.is_checked,
      updatedBy: row.updated_by,
      revision: row.revision,
    })),
    activity: activity.rows.map((row) => ({
      id: row.id,
      householdId,
      actorAccountId: row.actor_account_id ?? '',
      actorName: row.actor_name,
      kind: row.kind,
      mealTitle: row.meal_title,
      detail: row.detail,
      detailCode: activityDetailCode(row.detail_code),
      createdAt: new Date(row.created_at).toISOString().replace(/\.\d{3}Z$/, 'Z'),
    })),
  }
}

async function saveBoard(client: PoolClient, householdId: string, document: BoardDocument): Promise<void> {
  const preference = document.preference
  await client.query(
    `INSERT INTO household_preferences (
       household_id, cooking_days, max_weekday_minutes, preferred_categories, preferred_proteins, avoided_ingredients, revision, updated_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, now())
     ON CONFLICT (household_id) DO UPDATE
       SET cooking_days = EXCLUDED.cooking_days,
           max_weekday_minutes = EXCLUDED.max_weekday_minutes,
           preferred_categories = EXCLUDED.preferred_categories,
           preferred_proteins = EXCLUDED.preferred_proteins,
           avoided_ingredients = EXCLUDED.avoided_ingredients,
           revision = EXCLUDED.revision,
           updated_at = now()`,
    [
      householdId,
      preference.cookingDays,
      preference.maxWeekdayMinutes,
      preference.preferredCategories,
      preference.preferredProteins,
      preference.avoidedIngredients,
      preference.revision,
    ],
  )
  await client.query(
    `DELETE FROM meal_reactions
      WHERE shared_meal_id IN (
        SELECT m.id FROM shared_meals m
        JOIN shared_plans p ON p.id = m.plan_id
        WHERE p.household_id = $1
      )`,
    [householdId],
  )
  await client.query(
    `DELETE FROM shared_meals
      WHERE plan_id IN (SELECT id FROM shared_plans WHERE household_id = $1)`,
    [householdId],
  )
  await client.query('DELETE FROM shared_plans WHERE household_id = $1', [householdId])
  for (const plan of document.plans) {
    await client.query(
      `INSERT INTO shared_plans (id, household_id, week_start, status, is_finalized, revision, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, now())`,
      [plan.id, householdId, plan.weekStart, plan.status, plan.isFinalized, plan.revision],
    )
    for (const meal of plan.meals) {
      await client.query(
        `INSERT INTO shared_meals (
           id, plan_id, day_offset, recipe_slug, title, recipe_owner_account_id, status, revision, updated_at
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())`,
        [
          meal.id,
          plan.id,
          meal.dayOffset,
          meal.recipeSlug,
          meal.title,
          meal.recipeOwnerAccountId,
          meal.status,
          meal.revision,
        ],
      )
      for (const reaction of meal.reactions) {
        await client.query(
          `INSERT INTO meal_reactions (id, shared_meal_id, account_id, reaction, revision, created_at)
           VALUES ($1, $2, $3, $4, $5, now())`,
          [reaction.id, meal.id, reaction.accountId, reaction.reaction, reaction.revision],
        )
      }
    }
  }
  await client.query('DELETE FROM shared_grocery_items WHERE household_id = $1', [householdId])
  for (const item of document.grocery) {
    await client.query(
      `INSERT INTO shared_grocery_items (id, household_id, item_key, is_checked, updated_by, revision, quantity, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, now())`,
      [item.id, householdId, item.itemKey, item.isChecked, item.updatedBy, item.revision, item.quantity],
    )
  }
  await client.query('DELETE FROM household_activity WHERE household_id = $1', [householdId])
  for (const row of document.activity) {
    await client.query(
      `INSERT INTO household_activity (id, household_id, actor_account_id, actor_name, kind, meal_title, detail, detail_code, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [row.id, householdId, row.actorAccountId || null, row.actorName, row.kind, row.mealTitle, row.detail, row.detailCode, new Date(row.createdAt)],
    )
  }
}
