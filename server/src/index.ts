import { Pool } from 'pg'
import { buildApp } from './app.js'
import { assertRuntimeConfig, loadConfig } from './config.js'
import { loadEnvFile } from './env.js'
import { createJwksVerifier } from './jwks.js'
import { migrate } from './migrate.js'
import { createPgMigrationStore } from './pgMigration.js'
import { createPgRepository } from './pgRepository.js'

async function main(): Promise<void> {
  loadEnvFile()
  const config = loadConfig()
  assertRuntimeConfig(config)
  const pool = new Pool({ connectionString: config.databaseUrl })
  await migrate(pool)
  const app = buildApp({
    repo: createPgRepository(pool),
    migration: createPgMigrationStore(pool),
    config,
    verifier: createJwksVerifier(config),
    logger: true,
  })
  const address = await app.listen({ port: config.port, host: '0.0.0.0' })
  app.log.info({ address, apiVersion: config.apiVersion }, 'mealroutine api listening')
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'server failed'
  console.error(message)
  process.exit(1)
})
