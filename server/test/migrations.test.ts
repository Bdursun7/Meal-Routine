import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { buildIngredientIndex, resolveIngredientId, seedIngredients } from '../src/ingredients.js'
import { listMigrationFiles, migrationsDirectory } from '../src/migrate.js'

const requiredTables = [
  'schema_migrations',
  'accounts',
  'auth_identities',
  'sessions',
  'households',
  'household_members',
  'invites',
  'shared_plans',
  'shared_meals',
  'meal_reactions',
  'household_preferences',
  'shared_grocery_items',
  'household_activity',
  'personal_recipes',
  'meal_memory',
  'favorites',
  'cooking_history',
  'personal_preferences',
  'idempotency_keys',
  'entity_versions',
  'device_push_tokens',
  'notification_preferences',
  'api_schema_versions',
]

describe('migrations', () => {
  it('lists versioned SQL files in order and creates the phase-0 tables', async () => {
    const dir = migrationsDirectory()
    const files = await listMigrationFiles(dir)
    expect(files.map((file) => file.slice(0, 4))).toEqual(['0001', '0002', '0003', '0004', '0005', '0006', '0007', '0008', '0009', '0010', '0011', '0012'])
    const sql = (
      await Promise.all(files.map((file) => readFile(path.join(dir, file), 'utf8')))
    ).join('\n')
    for (const table of requiredTables) {
      expect(sql).toContain(table)
    }
    expect(sql).toContain('UNIQUE (provider, subject)')
    expect(sql).toContain('household member limit is 2')
    expect(sql).toContain('invites_one_pending')
    expect(sql).toContain('sync_changes')
    expect(sql).toContain('quantity')
    expect(sql).toContain('master_enabled')
    expect(sql).toContain('account_deletions')
    expect(sql).toContain('analytics_events')
    expect(sql).toContain('client_diagnostics')
    expect(sql).toContain('pantry_items')
    expect(sql).toContain('pantry_idempotency')
    for (const file of files.filter((name) => !name.startsWith('0012'))) {
      const earlier = await readFile(path.join(dir, file), 'utf8')
      expect(earlier).not.toContain('pantry_items')
    }
    expect(sql).toContain("'pending', 'accepted', 'rejected', 'cancelled', 'expired'")
    expect(sql).not.toContain('DROP TABLE')
  })

  it('keeps 0001-0011 untouched by V5 and seeds the same dictionary the app bundles', async () => {
    const dir = migrationsDirectory()
    const files = await listMigrationFiles(dir)
    for (const file of files.filter((name) => !name.startsWith('0012'))) {
      const earlier = await readFile(path.join(dir, file), 'utf8')
      for (const marker of ['TABLE IF NOT EXISTS ingredients', 'date_type', 'pantry_']) expect(earlier, file).not.toContain(marker)
    }
    const pantry = await readFile(path.join(dir, files.find((name) => name.startsWith('0012'))!), 'utf8')
    for (const marker of ['CREATE TABLE IF NOT EXISTS ingredients', 'REFERENCES ingredients (id)', "date_type IN ('bestBefore', 'useBy')", 'pantry_items_date_pair', 'unit_bucket', 'pantry_items_one_row_per_bucket', 'version INT']) {
      expect(pantry).toContain(marker)
    }
    expect(pantry).not.toContain('best_before')
    expect(pantry).not.toMatch(/^\s*(DROP|DELETE FROM|TRUNCATE|ALTER TABLE)\b/im)

    const serverCopy = await readFile(path.resolve(dir, '../ingredients.v1.json'), 'utf8')
    const appCopy = await readFile(path.resolve(dir, '../../../MealRoutine/Recipes/ingredients.v1.json'), 'utf8')
    expect(appCopy).toBe(serverCopy)
    const seeded = [...pantry.matchAll(/^ {2}\('([^']+)', /gm)].map((match) => match[1])
    expect(seeded).toEqual(seedIngredients().map((row) => row.id))
  })

  it('covers every catalog ingredient id so recipe lines can reach the dictionary', async () => {
    const catalog = JSON.parse(await readFile(path.resolve(migrationsDirectory(), '../../../MealRoutine/Recipes/recipes.v1.json'), 'utf8')) as {
      recipes: { ingredients: { id: string }[] }[]
    }
    const index = buildIngredientIndex(seedIngredients())
    const missing = new Set<string>()
    for (const recipe of catalog.recipes) {
      for (const line of recipe.ingredients) if (!resolveIngredientId(index, line.id)) missing.add(line.id)
    }
    expect([...missing]).toEqual([])
  })
})
