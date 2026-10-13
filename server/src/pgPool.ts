import { Pool, type PoolConfig } from 'pg'

/** Enough of the Fastify logger to record an idle-client failure. */
export interface PoolErrorLogger {
  warn(obj: { err: unknown }, message: string): void
}

const idleClientErrorMessage = 'unexpected error on idle postgres client'

/**
 * pg-pool's idleListener removes a checked-in client and then emits `error`
 * on the pool (`Connection terminated unexpectedly`). With no listener, Node
 * treats that as an unhandled 'error' event and exits. The dead client is
 * already gone, so the next query checks out a new one. Log and keep serving.
 */
export function createDatabasePool(config: PoolConfig, logger: PoolErrorLogger): Pool {
  const pool = new Pool({
    ...config,
    keepAlive: true,
  })
  pool.on('error', (err) => {
    logger.warn({ err }, idleClientErrorMessage)
  })
  return pool
}

/** Used by the migration CLI, and by the server until the Fastify logger exists. */
export function consolePoolLogger(): PoolErrorLogger {
  return {
    warn(obj, message) {
      const detail = obj.err instanceof Error ? obj.err.message : 'unknown error'
      console.warn(`${message}: ${detail}`)
    },
  }
}
