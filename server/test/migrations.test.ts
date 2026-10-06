import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
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
})
