import { execFileSync } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { copyFile, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { Pool } from 'pg'
import { afterAll, describe, expect, it } from 'vitest'
import { listMigrationFiles, migrate, migrationsDirectory } from '../src/migrate.js'

const databaseUrl = process.env.DATABASE_URL

// A database that recorded the early foundation 0012 (commit 3cd0695) has no unit_bucket column.
// Before the repair, 0015 failed with `column "unit_bucket" named in key does not exist`.
describe.skipIf(!databaseUrl)('postgres pantry foundation repair', () => {
  const schema = `mr_found_${randomBytes(4).toString('hex')}`
  const admin = new Pool({ connectionString: databaseUrl })
  const pool = new Pool({ connectionString: databaseUrl, options: `-c search_path=${schema}` })

  afterAll(async () => {
    await pool.end()
    await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`)
    await admin.end()
  })

  it('repairs the early 0012 schema, keeps its rows, and applies 0015', async () => {
    await admin.query(`CREATE SCHEMA ${schema}`)
    const dir = await mkdtemp(path.join(tmpdir(), 'mr-found-'))
    const files = await listMigrationFiles(migrationsDirectory())
    for (const file of files.filter((name) => name < '0012' || (name >= '0013' && name < '0015'))) {
      await copyFile(path.join(migrationsDirectory(), file), path.join(dir, file))
    }
    const early = execFileSync('git', ['show', '3cd0695:server/db/migrations/0012_pantry.sql'], { cwd: migrationsDirectory() }).toString()
    await writeFile(path.join(dir, '0012_pantry.sql'), early)
    expect(await migrate(pool, dir)).toEqual(files.filter((n) => n < '0015').map((n) => n.replace(/\.sql$/, '')))
    await rm(dir, { recursive: true, force: true })

    await pool.query(`INSERT INTO accounts (id, display_name) VALUES ('11111111-1111-4111-8111-111111111111', 'Ada')`)
    await pool.query(`INSERT INTO households (id, name, owner_account_id) VALUES ('22222222-2222-4222-8222-222222222222', 'Ev', '11111111-1111-4111-8111-111111111111')`)
    await pool.query(`INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location, minimum_quantity, best_before, revision) VALUES
      ('33333333-3333-4333-8333-333333333331', '22222222-2222-4222-8222-222222222222', 'tomato', 'Domates', 2, 'kg', 'refrigerator', 0.5, '2030-01-01', 3),
      ('33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'not-in-dictionary', 'X', 1, 'piece', 'pantry', NULL, NULL, 1)`)

    expect(await migrate(pool)).toEqual(['0012_pantry', '0013_pantry_auto_add', '0015_pantry_location'])
    const rows = (await pool.query(`SELECT id::text, unit_bucket, date_type, to_char(date_value, 'YYYY-MM-DD') AS date_value, version, auto_add_to_grocery FROM pantry_items`)).rows
    expect(rows).toEqual([{ id: '33333333-3333-4333-8333-333333333331', unit_bucket: 'mass', date_type: 'bestBefore', date_value: '2030-01-01', version: 3, auto_add_to_grocery: false }])
    const kept = await pool.query<{ count: string }>('SELECT count(*) FROM pantry_items_foundation_0012')
    expect(Number(kept.rows[0]!.count)).toBe(2)
    expect(await migrate(pool)).toEqual([])
  })
})
