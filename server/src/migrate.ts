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
