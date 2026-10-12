import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Pool } from 'pg'
import { loadConfig } from './config.js'
import { loadEnvFile } from './env.js'

export function migrationsDirectory(): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../db/migrations')
}

export async function listMigrationFiles(dir: string): Promise<string[]> {
  const names = await readdir(dir)
  return names.filter((name) => /^\d{4}_.+\.sql$/.test(name)).sort()
}

export async function migrate(pool: Pool, dir = migrationsDirectory()): Promise<string[]> {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`)
  const files = await listMigrationFiles(dir)
  await repairFoundationPantry(pool)
  const applied: string[] = []
  for (const file of files) {
    const version = file.replace(/\.sql$/, '')
    const existing = await pool.query('SELECT 1 FROM schema_migrations WHERE version = $1', [version])
    if ((existing.rowCount ?? 0) > 0) continue
    const sql = await readFile(path.join(dir, file), 'utf8')
    const client = await pool.connect()
    try {
      await client.query('BEGIN')
      await client.query(sql)
      await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [version])
      await client.query('COMMIT')
      applied.push(version)
    } catch (error) {
      await client.query('ROLLBACK')
      throw error
    } finally {
      client.release()
    }
  }
  return applied
}

/**
 * The first V5 foundation commit (3cd0695) shipped an early `0012_pantry.sql` with
 * `unit`/`best_before`/`revision` columns, no `ingredients` table and no `unit_bucket`.
 * 0012 was later rewritten in place, so a database that recorded the early 0012 never
 * received the canonical schema and 0015 fails with `column "unit_bucket" ... does not exist`.
 *
 * Repair, in one transaction: keep the early tables under `*_foundation_0012` names
 * (no data is dropped) and forget 0012/0013 so the loop applies the canonical files.
 * 0015 then copies the convertible foundation rows back into `pantry_items`.
 */
export async function repairFoundationPantry(pool: Pool): Promise<boolean> {
  const client = await pool.connect()
  try {
    await client.query('BEGIN')
    const legacy = await client.query(
      `SELECT 1 FROM information_schema.columns
       WHERE table_schema = current_schema() AND table_name = 'pantry_items' AND column_name = 'best_before'`,
    )
    if ((legacy.rowCount ?? 0) === 0) {
      await client.query('ROLLBACK')
      return false
    }
    await client.query('ALTER TABLE pantry_items RENAME TO pantry_items_foundation_0012')
    await client.query('ALTER INDEX IF EXISTS pantry_items_household_idx RENAME TO pantry_items_foundation_0012_household_idx')
    await client.query('ALTER TABLE IF EXISTS pantry_idempotency RENAME TO pantry_idempotency_foundation_0012')
    await client.query(`DELETE FROM schema_migrations WHERE version IN ('0012_pantry', '0013_pantry_auto_add', '0015_pantry_location')`)
    await client.query('COMMIT')
    console.log('Repaired foundation pantry schema: early tables kept as *_foundation_0012; 0012/0013 will be re-applied.')
    return true
  } catch (error) {
    await client.query('ROLLBACK')
    throw error
  } finally {
    client.release()
  }
}

async function main(): Promise<void> {
  loadEnvFile()
  const config = loadConfig()
  if (!config.databaseUrl) {
    throw new Error('DATABASE_URL is required. See server/db/README.md.')
  }
  const pool = new Pool({ connectionString: config.databaseUrl })
  try {
    const applied = await migrate(pool)
    if (applied.length === 0) {
      console.log('Migrations already applied.')
    } else {
      console.log(`Applied: ${applied.join(', ')}`)
    }
  } finally {
    await pool.end()
  }
}

const invoked = process.argv[1] ? path.resolve(process.argv[1]) : ''
if (invoked.endsWith(`${path.sep}migrate.ts`) || invoked.endsWith(`${path.sep}migrate.js`)) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : 'migration failed'
    console.error(message)
    process.exit(1)
  })
}
