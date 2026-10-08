import { createHash } from 'node:crypto'
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
    expect(files.map((file) => file.slice(0, 4))).toEqual(['0001', '0002', '0003', '0004', '0005', '0006', '0007', '0008', '0009', '0010', '0011', '0012', '0013'])
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
    for (const file of files.filter((name) => name < '0012')) {
      const earlier = await readFile(path.join(dir, file), 'utf8')
      expect(earlier).not.toContain('pantry_items')
    }
    expect(sql).toContain("'pending', 'accepted', 'rejected', 'cancelled', 'expired'")
    expect(sql).not.toContain('DROP TABLE')
  })

  it('keeps 0001-0011 untouched by V5 and seeds the same dictionary the app bundles', async () => {
    const dir = migrationsDirectory()
    const files = await listMigrationFiles(dir)
    for (const file of files.filter((name) => name < '0012')) {
      const earlier = await readFile(path.join(dir, file), 'utf8')
      for (const marker of ['TABLE IF NOT EXISTS ingredients', 'date_type', 'pantry_']) expect(earlier, file).not.toContain(marker)
    }
    const pantry = await readFile(path.join(dir, files.find((name) => name.startsWith('0012'))!), 'utf8')
    for (const marker of ['CREATE TABLE IF NOT EXISTS ingredients', 'REFERENCES ingredients (id)', "date_type IN ('bestBefore', 'useBy')", 'pantry_items_date_pair', 'unit_bucket', 'pantry_items_one_row_per_bucket', 'version INT']) {
      expect(pantry).toContain(marker)
    }
    expect(pantry).not.toContain('best_before')
    expect(pantry).not.toMatch(/^\s*(DROP|DELETE FROM|TRUNCATE|ALTER TABLE)\b/im)

    const serverCopy = await readFile(path.resolve(dir, '../ingredients.v2.json'), 'utf8')
    const appCopy = await readFile(path.resolve(dir, '../../../MealRoutine/Recipes/ingredients.v2.json'), 'utf8')
    expect(appCopy).toBe(serverCopy)
    const seeded = [...pantry.matchAll(/^ {2}\('([^']+)', /gm)].map((match) => match[1])
    expect(seeded).toEqual(seedIngredients().map((row) => row.id))
  })

  it('never edits a shipped migration: 0001-0012 are byte-for-byte frozen', async () => {
    const dir = migrationsDirectory()
    const frozen: Record<string, string> = {
      '0001_schema_migrations.sql': '45964b8391d40b1a8dc923a877692eeb7c1a6e097f413e6ad96072548d7c34ec',
      '0002_accounts_and_auth.sql': 'c5f9f48b97f34b433245d6b5f23a6bfd6fb236937c73f94cf4a3b47bfd6b401d',
      '0003_households.sql': 'ba498fe4bcc66a95fbc5303780f5dd660b281565575d2a928d63eef932f50fd2',
      '0004_shared_plan.sql': 'ccd5a7ff88a5c9c0fbcd1b1c992d52601f93b0ac260b14c9288cf2f6d2295460',
      '0005_personal_data.sql': '658b1ce6b032774033ff4ec84c78794a47d899b28e4b84c3bee0641ac4d05dd9',
      '0006_sync_notifications_versioning.sql': '618e0d1456d2914791859d7a9a85be46a8a7aad47a43bb5a114f4818b46362dd',
      '0007_one_pending_invite.sql': 'f0d6a5b87dd65a7bd385fac540fe442794bc6a86bd0ec79679e57e792acad5fe',
      '0008_sync_changes.sql': 'd77f1f43a99c5d0196e0f66048d77703868111afdb73d65a85669bd22b4c6786',
      '0009_notification_delivery.sql': 'd5ee3d10e6e5986ad81599bde09297f0971cd9ad473438a0455ef420a0d3473c',
      '0010_account_deletion.sql': '4026ce60c53e27f5ba1b89b6383a258aba3c7b5648778196ff4a9ecdca9258e4',
      '0011_observability.sql': '63de0c7ecec84ff4022edfdf65a18b1285a57f2b6f8de8958583d0ccb9d7e74f',
      '0012_pantry.sql': '79f5268ead4d4cbc3f613128291770f559f744ff191d6d3d0165d6e33923b9e6',
    }
    for (const [file, digest] of Object.entries(frozen)) {
      const body = await readFile(path.join(dir, file))
      expect(createHash('sha256').update(body).digest('hex'), file).toBe(digest)
    }
  })

  it('0013 adds regional context, locale-keyed ingredient names, new units and the week-start fix', async () => {
    const dir = migrationsDirectory()
    const sql = await readFile(path.join(dir, '0013_globalization.sql'), 'utf8')
    for (const column of ['locale', 'country_code', 'currency_code', 'measurement_system', 'timezone']) {
      expect(sql).toContain(`ADD COLUMN IF NOT EXISTS ${column} TEXT NOT NULL DEFAULT`)
      expect(sql).toContain(`ALTER COLUMN ${column} DROP DEFAULT`)
    }
    for (const literal of ["'tr-TR'", "'TR'", "'TRY'", "'metric'", "'Europe/Istanbul'"]) expect(sql).toContain(literal)
    for (const marker of ['CREATE TABLE IF NOT EXISTS ingredient_names', 'CREATE TABLE IF NOT EXISTS ingredient_aliases', 'pantry_items_unit_code', 'EXTRACT(ISODOW FROM p.week_start) = 7', 'detail_code']) {
      expect(sql).toContain(marker)
    }
    for (const unit of ['oz', 'lb', 'cup', 'package', 'can', 'bottle']) expect(sql).toContain(`'${unit}'`)
    expect(sql).not.toMatch(/\bDROP TABLE\b|\bTRUNCATE\b|\bDELETE FROM\b/i)
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
