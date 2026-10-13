import { buildApp } from './app.js'
import { assertRuntimeConfig, loadConfig } from './config.js'
import { loadEnvFile } from './env.js'
import { createJwksVerifier } from './jwks.js'
import { migrate } from './migrate.js'
import { createPgNotificationStore, createPushSender, DISPATCH_INTERVAL_MS } from './notifications.js'
import { createErrorReporter } from './observability.js'
import { createPgMigrationStore } from './pgMigration.js'
import { createPgObservability } from './pgObservability.js'
import { consolePoolLogger, createDatabasePool } from './pgPool.js'
import { createPgRepository } from './pgRepository.js'

async function main(): Promise<void> {
  loadEnvFile()
  const config = loadConfig()
  assertRuntimeConfig(config)
  const poolLogger = consolePoolLogger()
  const pool = createDatabasePool({ connectionString: config.databaseUrl }, poolLogger)
  await migrate(pool)
  const app = buildApp({
    repo: createPgRepository(pool),
    migration: createPgMigrationStore(pool),
    notifications: createPgNotificationStore(pool),
    sender: createPushSender(),
    observability: createPgObservability(pool),
    errorReporter: createErrorReporter(config.sentryDsn),
    readiness: async () => {
      try {
        await pool.query('SELECT 1')
        return true
      } catch {
        return false
      }
    },
    config,
    verifier: createJwksVerifier(config),
    logger: true,
    dispatchIntervalMs: DISPATCH_INTERVAL_MS,
  })
  // Startup errors use stderr. From here, idle-client failures go through the app logger.
  poolLogger.warn = (obj, message) => {
    app.log.warn(obj, message)
  }
  // A listener suppresses Node's default crash, so exit after logging.
  // Leave uncaughtException alone: catching it and continuing would hide a fatal error.
  process.on('unhandledRejection', (reason: unknown) => {
    try {
      app.log.error({ err: reason }, 'unhandledRejection')
    } finally {
      process.exit(1)
    }
  })
  const address = await app.listen({ port: config.port, host: '0.0.0.0' })
  app.log.info({ address, apiVersion: config.apiVersion }, 'mealroutine api listening')
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'server failed'
  console.error(message)
  process.exit(1)
})
