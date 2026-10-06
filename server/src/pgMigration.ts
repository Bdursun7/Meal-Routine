import type { Pool, PoolClient } from 'pg'
import type { MigrationMemory, MigrationRecipe, PersonalBundle } from './migrationRules.js'
import type { MigrationStore } from './migrationService.js'

export function createPgMigrationStore(pool: Pool): MigrationStore {
  return {
    async load(accountId) {
      const client = await pool.connect()
      try {
        return await loadBundle(client, accountId)
      } finally {
        client.release()
      }
    },
    async save(accountId, bundle, status) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        await saveBundle(client, accountId, bundle, status)
        await client.query('COMMIT')
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      } finally {
        client.release()
      }
    },
    async claimHistory(accountId, ids) {
      return claim(pool, 'cooking_history', accountId, ids)
    },
    async claimFeedback(accountId, ids) {
      return claim(pool, 'recipe_feedback', accountId, ids)
    },
    async erase(accountId) {
      await pool.query(`DELETE FROM personal_recipes WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM meal_memory WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM favorites WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM cooking_history WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM recipe_feedback WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM personal_preferences WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM personal_migrations WHERE account_id = $1`, [accountId])
    },
  }
}

async function claim(pool: Pool, table: 'cooking_history' | 'recipe_feedback', accountId: string, ids: string[]) {
  const allowed = new Set(ids)
  const uuids = ids.filter(isUuid)
  if (uuids.length === 0) return allowed
  const result = await pool.query<{ id: string; account_id: string }>(
    `SELECT id::text, account_id::text FROM ${table} WHERE id = ANY($1::uuid[])`,
    [uuids],
  )
  for (const row of result.rows) {
    if (row.account_id !== accountId) allowed.delete(row.id)
  }
  return allowed
}

async function loadBundle(client: PoolClient, accountId: string): Promise<{ bundle: PersonalBundle; status: 'not_started' | 'uploaded' | 'confirmed' }> {
  const statusRow = await client.query<{ status: string }>(
    'SELECT status FROM personal_migrations WHERE account_id = $1',
    [accountId],
  )
  const status = (statusRow.rows[0]?.status ?? 'not_started') as 'not_started' | 'uploaded' | 'confirmed'
  const preferences = await client.query(
    `SELECT household_size, evenings_per_week, max_cook_minutes, disliked_ingredient_ids, discovery_level,
            repeat_preference, difficulty_preference, weekday_style, dismissed_pattern_ids,
            has_completed_onboarding, updated_at
       FROM personal_preferences WHERE account_id = $1`,
    [accountId],
  )
  const recipes = await client.query(
    `SELECT id::text, slug, name_tr, name_en, summary_tr, origin, collection_state, source_url, source_key,
            source_platform, source_title, user_notes, base_servings, prep_minutes, cook_minutes, total_minutes,
            time_is_unknown, servings_unspecified, difficulty, category, country, diets, tags, photo_url, updated_at
       FROM personal_recipes WHERE account_id = $1`,
    [accountId],
  )
  const recipeIds = recipes.rows.map((row) => row.id as string)
  const ingredients = recipeIds.length
    ? await client.query(
        `SELECT id::text, recipe_id::text, sort_index, ingredient_id, name_tr, name_en, quantity, unit, note_tr, is_optional, include_in_grocery
           FROM personal_recipe_ingredients WHERE recipe_id = ANY($1::uuid[]) ORDER BY sort_index`,
        [recipeIds],
      )
    : { rows: [] as Record<string, unknown>[] }
  const steps = recipeIds.length
    ? await client.query(
        `SELECT id::text, recipe_id::text, sort_index, text_tr, text_en, minutes
           FROM personal_recipe_steps WHERE recipe_id = ANY($1::uuid[]) ORDER BY sort_index`,
        [recipeIds],
      )
    : { rows: [] as Record<string, unknown>[] }
  const memories = await client.query('SELECT * FROM meal_memory WHERE account_id = $1', [accountId])
  const favorites = await client.query(
    'SELECT recipe_slug, created_at FROM favorites WHERE account_id = $1',
    [accountId],
  )
  const history = await client.query(
    `SELECT id::text, recipe_slug, event_type, plan_week_id::text, planned_meal_id::text, replacement_reason, created_at
       FROM cooking_history WHERE account_id = $1`,
    [accountId],
  )
  const feedback = await client.query(
    `SELECT id::text, recipe_slug, rating, cooked, reasons, created_at FROM recipe_feedback WHERE account_id = $1`,
    [accountId],
  )
  const pref = preferences.rows[0]
  const bundle: PersonalBundle = {
    preferences: pref
      ? {
          updatedAt: iso(pref.updated_at),
          householdSize: Number(pref.household_size),
          eveningsPerWeek: Number(pref.evenings_per_week),
          maxCookMinutes: Number(pref.max_cook_minutes),
          dislikedIngredientIds: pref.disliked_ingredient_ids ?? [],
          discoveryLevel: pref.discovery_level,
          repeatPreference: pref.repeat_preference,
          difficultyPreference: pref.difficulty_preference,
          weekdayStyle: pref.weekday_style,
          dismissedPatternIds: pref.dismissed_pattern_ids ?? [],
          hasCompletedOnboarding: Boolean(pref.has_completed_onboarding),
        }
      : null,
    recipes: recipes.rows.map((row) => recipeFrom(row, ingredients.rows, steps.rows)),
    memories: memories.rows.map(memoryFrom),
    favorites: favorites.rows.map((row) => ({ recipeSlug: row.recipe_slug, createdAt: iso(row.created_at) })),
    history: history.rows.map((row) => ({
      id: row.id,
      recipeSlug: row.recipe_slug,
      eventType: row.event_type,
      planWeekId: row.plan_week_id,
      plannedMealId: row.planned_meal_id,
      replacementReason: row.replacement_reason,
      createdAt: iso(row.created_at),
    })),
    feedback: feedback.rows.map((row) => ({
      id: row.id,
      recipeSlug: row.recipe_slug,
      rating: row.rating,
      cooked: Boolean(row.cooked),
      reasons: row.reasons ?? [],
      createdAt: iso(row.created_at),
    })),
  }
  return { bundle, status }
}

async function saveBundle(client: PoolClient, accountId: string, bundle: PersonalBundle, status: 'uploaded' | 'confirmed' | 'not_started') {
  if (bundle.preferences) {
    const pref = bundle.preferences
    await client.query(
      `INSERT INTO personal_preferences (
         account_id, household_size, evenings_per_week, max_cook_minutes, disliked_ingredient_ids,
         discovery_level, repeat_preference, difficulty_preference, weekday_style, dismissed_pattern_ids,
         has_completed_onboarding, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
       ON CONFLICT (account_id) DO UPDATE SET
         household_size = EXCLUDED.household_size,
         evenings_per_week = EXCLUDED.evenings_per_week,
         max_cook_minutes = EXCLUDED.max_cook_minutes,
         disliked_ingredient_ids = EXCLUDED.disliked_ingredient_ids,
         discovery_level = EXCLUDED.discovery_level,
         repeat_preference = EXCLUDED.repeat_preference,
         difficulty_preference = EXCLUDED.difficulty_preference,
         weekday_style = EXCLUDED.weekday_style,
         dismissed_pattern_ids = EXCLUDED.dismissed_pattern_ids,
         has_completed_onboarding = EXCLUDED.has_completed_onboarding,
         updated_at = EXCLUDED.updated_at,
         revision = personal_preferences.revision + 1`,
      [
        accountId, pref.householdSize, pref.eveningsPerWeek, pref.maxCookMinutes, pref.dislikedIngredientIds,
        pref.discoveryLevel, pref.repeatPreference, pref.difficultyPreference, pref.weekdayStyle,
        pref.dismissedPatternIds, pref.hasCompletedOnboarding, pref.updatedAt,
      ],
    )
  }
  for (const recipe of bundle.recipes) {
    await client.query(
      `INSERT INTO personal_recipes (
         id, account_id, slug, name_tr, name_en, summary_tr, origin, collection_state, source_url, source_key,
         source_platform, source_title, user_notes, base_servings, prep_minutes, cook_minutes, total_minutes,
         time_is_unknown, servings_unspecified, difficulty, category, country, diets, tags, photo_url, updated_at
       ) VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26
       )
       ON CONFLICT (account_id, slug) DO UPDATE SET
         name_tr = EXCLUDED.name_tr, name_en = EXCLUDED.name_en, summary_tr = EXCLUDED.summary_tr,
         origin = EXCLUDED.origin, collection_state = EXCLUDED.collection_state, source_url = EXCLUDED.source_url,
         source_key = EXCLUDED.source_key, source_platform = EXCLUDED.source_platform, source_title = EXCLUDED.source_title,
         user_notes = EXCLUDED.user_notes, base_servings = EXCLUDED.base_servings, prep_minutes = EXCLUDED.prep_minutes,
         cook_minutes = EXCLUDED.cook_minutes, total_minutes = EXCLUDED.total_minutes,
         time_is_unknown = EXCLUDED.time_is_unknown, servings_unspecified = EXCLUDED.servings_unspecified,
         difficulty = EXCLUDED.difficulty, category = EXCLUDED.category, country = EXCLUDED.country,
         diets = EXCLUDED.diets, tags = EXCLUDED.tags, photo_url = EXCLUDED.photo_url, updated_at = EXCLUDED.updated_at,
         revision = personal_recipes.revision + 1`,
      [
        recipe.id, accountId, recipe.slug, recipe.nameTr, recipe.nameEn, recipe.summaryTr, recipe.origin,
        recipe.collectionState, recipe.sourceUrl, recipe.sourceKey, recipe.sourcePlatform, recipe.sourceTitle,
        recipe.userNotes, recipe.baseServings, recipe.prepMinutes, recipe.cookMinutes, recipe.totalMinutes,
        recipe.timeIsUnknown, recipe.servingsUnspecified, recipe.difficulty, recipe.category, recipe.country,
        recipe.diets, recipe.tags, recipe.photoUrl, recipe.updatedAt,
      ],
    )
    const stored = await client.query<{ id: string }>(
      'SELECT id::text FROM personal_recipes WHERE account_id = $1 AND slug = $2',
      [accountId, recipe.slug],
    )
    const recipeId = stored.rows[0]?.id ?? recipe.id
    await client.query('DELETE FROM personal_recipe_ingredients WHERE recipe_id = $1', [recipeId])
    await client.query('DELETE FROM personal_recipe_steps WHERE recipe_id = $1', [recipeId])
    for (const line of recipe.ingredients) {
      await client.query(
        `INSERT INTO personal_recipe_ingredients (
           id, recipe_id, sort_index, ingredient_id, name_tr, name_en, quantity, unit, note_tr, is_optional, include_in_grocery
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [line.id, recipeId, line.sortIndex, line.ingredientId, line.nameTr, line.nameEn, line.quantity, line.unit, line.noteTr, line.isOptional, line.includeInGrocery],
      )
    }
    for (const step of recipe.steps) {
      await client.query(
        `INSERT INTO personal_recipe_steps (id, recipe_id, sort_index, text_tr, text_en, minutes)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [step.id, recipeId, step.sortIndex, step.textTr, step.textEn, step.minutes],
      )
    }
  }
  for (const memory of bundle.memories) {
    await client.query(
      `INSERT INTO meal_memory (
         account_id, recipe_slug, times_cooked, times_replaced, times_skipped, last_cooked_at, last_selected_at,
         loved_count, okay_count, latest_rating, never_again, time_concern_count, difficulty_concern_count,
         portion_concern_count, missing_ingredient_count, too_many_ingredient_count, would_make_again_count,
         is_favorite, discovery_status, confidence, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
       ON CONFLICT (account_id, recipe_slug) DO UPDATE SET
         times_cooked = EXCLUDED.times_cooked, times_replaced = EXCLUDED.times_replaced, times_skipped = EXCLUDED.times_skipped,
         last_cooked_at = EXCLUDED.last_cooked_at, last_selected_at = EXCLUDED.last_selected_at,
         loved_count = EXCLUDED.loved_count, okay_count = EXCLUDED.okay_count, latest_rating = EXCLUDED.latest_rating,
         never_again = EXCLUDED.never_again, time_concern_count = EXCLUDED.time_concern_count,
         difficulty_concern_count = EXCLUDED.difficulty_concern_count, portion_concern_count = EXCLUDED.portion_concern_count,
         missing_ingredient_count = EXCLUDED.missing_ingredient_count, too_many_ingredient_count = EXCLUDED.too_many_ingredient_count,
         would_make_again_count = EXCLUDED.would_make_again_count, is_favorite = EXCLUDED.is_favorite,
         discovery_status = EXCLUDED.discovery_status, confidence = EXCLUDED.confidence, updated_at = EXCLUDED.updated_at,
         revision = meal_memory.revision + 1`,
      [
        accountId, memory.recipeSlug, memory.timesCooked, memory.timesReplaced, memory.timesSkipped,
        memory.lastCookedAt, memory.lastSelectedAt, memory.lovedCount, memory.okayCount, memory.latestRating,
        memory.neverAgain, memory.timeConcernCount, memory.difficultyConcernCount, memory.portionConcernCount,
        memory.missingIngredientCount, memory.tooManyIngredientCount, memory.wouldMakeAgainCount, memory.isFavorite,
        memory.discoveryStatus, memory.confidence, memory.updatedAt,
      ],
    )
  }
  for (const favorite of bundle.favorites) {
    await client.query(
      `INSERT INTO favorites (account_id, recipe_slug, created_at) VALUES ($1,$2,$3)
       ON CONFLICT (account_id, recipe_slug) DO NOTHING`,
      [accountId, favorite.recipeSlug, favorite.createdAt],
    )
  }
  for (const row of bundle.history) {
    await client.query(
      `INSERT INTO cooking_history (id, account_id, recipe_slug, event_type, plan_week_id, planned_meal_id, replacement_reason, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (id) DO NOTHING`,
      [row.id, accountId, row.recipeSlug, row.eventType, row.planWeekId, row.plannedMealId, row.replacementReason, row.createdAt],
    )
  }
  for (const row of bundle.feedback) {
    await client.query(
      `INSERT INTO recipe_feedback (id, account_id, recipe_slug, rating, cooked, reasons, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (id) DO NOTHING`,
      [row.id, accountId, row.recipeSlug, row.rating, row.cooked, row.reasons, row.createdAt],
    )
  }
  await client.query(
    `INSERT INTO personal_migrations (account_id, status, confirmed_at)
     VALUES ($1, $2, CASE WHEN $2 = 'confirmed' THEN now() ELSE NULL END)
     ON CONFLICT (account_id) DO UPDATE SET
       status = EXCLUDED.status,
       confirmed_at = CASE WHEN EXCLUDED.status = 'confirmed' THEN COALESCE(personal_migrations.confirmed_at, now()) ELSE personal_migrations.confirmed_at END`,
    [accountId, status === 'not_started' ? 'pending' : status],
  )
}

function recipeFrom(row: Record<string, unknown>, ingredients: Record<string, unknown>[], steps: Record<string, unknown>[]): MigrationRecipe {
  const id = String(row.id)
  return {
    id,
    slug: String(row.slug),
    updatedAt: iso(row.updated_at),
    nameTr: String(row.name_tr ?? ''),
    nameEn: String(row.name_en ?? ''),
    summaryTr: String(row.summary_tr ?? ''),
    origin: String(row.origin ?? ''),
    collectionState: String(row.collection_state ?? ''),
    sourceUrl: String(row.source_url ?? ''),
    sourceKey: String(row.source_key ?? ''),
    sourcePlatform: String(row.source_platform ?? ''),
    sourceTitle: String(row.source_title ?? ''),
    userNotes: String(row.user_notes ?? ''),
    baseServings: Number(row.base_servings ?? 0),
    prepMinutes: Number(row.prep_minutes ?? 0),
    cookMinutes: Number(row.cook_minutes ?? 0),
    totalMinutes: Number(row.total_minutes ?? 0),
    timeIsUnknown: Boolean(row.time_is_unknown),
    servingsUnspecified: Boolean(row.servings_unspecified),
    difficulty: String(row.difficulty ?? ''),
    category: String(row.category ?? ''),
    country: String(row.country ?? ''),
    diets: (row.diets as string[]) ?? [],
    tags: (row.tags as string[]) ?? [],
    photoUrl: String(row.photo_url ?? ''),
    ingredients: ingredients.filter((line) => line.recipe_id === id).map((line) => ({
      id: String(line.id),
      sortIndex: Number(line.sort_index),
      ingredientId: String(line.ingredient_id ?? ''),
      nameTr: String(line.name_tr ?? ''),
      nameEn: String(line.name_en ?? ''),
      quantity: line.quantity == null ? null : Number(line.quantity),
      unit: String(line.unit ?? ''),
      noteTr: String(line.note_tr ?? ''),
      isOptional: Boolean(line.is_optional),
      includeInGrocery: Boolean(line.include_in_grocery),
    })),
    steps: steps.filter((step) => step.recipe_id === id).map((step) => ({
      id: String(step.id),
      sortIndex: Number(step.sort_index),
      textTr: String(step.text_tr ?? ''),
      textEn: String(step.text_en ?? ''),
      minutes: step.minutes == null ? null : Number(step.minutes),
    })),
  }
}

function memoryFrom(row: Record<string, unknown>): MigrationMemory {
  return {
    recipeSlug: String(row.recipe_slug),
    updatedAt: iso(row.updated_at),
    timesCooked: Number(row.times_cooked ?? 0),
    timesReplaced: Number(row.times_replaced ?? 0),
    timesSkipped: Number(row.times_skipped ?? 0),
    lastCookedAt: row.last_cooked_at ? iso(row.last_cooked_at) : null,
    lastSelectedAt: row.last_selected_at ? iso(row.last_selected_at) : null,
    lovedCount: Number(row.loved_count ?? 0),
    okayCount: Number(row.okay_count ?? 0),
    latestRating: String(row.latest_rating ?? ''),
    neverAgain: Boolean(row.never_again),
    timeConcernCount: Number(row.time_concern_count ?? 0),
    difficultyConcernCount: Number(row.difficulty_concern_count ?? 0),
    portionConcernCount: Number(row.portion_concern_count ?? 0),
    missingIngredientCount: Number(row.missing_ingredient_count ?? 0),
    tooManyIngredientCount: Number(row.too_many_ingredient_count ?? 0),
    wouldMakeAgainCount: Number(row.would_make_again_count ?? 0),
    isFavorite: Boolean(row.is_favorite),
    discoveryStatus: String(row.discovery_status ?? ''),
    confidence: String(row.confidence ?? ''),
  }
}

function iso(value: unknown): string {
  if (value instanceof Date) return value.toISOString()
  return new Date(String(value)).toISOString()
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}
