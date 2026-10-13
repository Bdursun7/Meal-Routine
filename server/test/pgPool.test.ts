import { EventEmitter } from 'node:events'
import type { PoolConfig } from 'pg'
import { describe, expect, it, vi } from 'vitest'
import { createDatabasePool } from '../src/pgPool.js'

const idleClientErrorMessage = 'unexpected error on idle postgres client'

describe('postgres pool', () => {
  it('does not throw when the pool emits an idle client error', async () => {
    const warn = vi.fn()
    const exit = vi.spyOn(process, 'exit').mockImplementation((() => undefined) as typeof process.exit)
    const pool = createDatabasePool(
      { connectionString: 'postgres://127.0.0.1:1/none', keepAlive: false },
      { warn },
    )
    try {
      const error = new Error('Connection terminated unexpectedly')
      expect(() => {
        pool.emit('error', error)
      }).not.toThrow()
      expect(warn).toHaveBeenCalledTimes(1)
      expect(warn).toHaveBeenCalledWith({ err: error }, idleClientErrorMessage)
      expect(exit).not.toHaveBeenCalled()
      expect(pool.options.keepAlive).toBe(true)
      expect(pool.listenerCount('error')).toBeGreaterThan(0)
    } finally {
      exit.mockRestore()
      await pool.end()
    }
  })

  it('checks out a fresh client after an idle connection is dropped', async () => {
    const clients: IdleClient[] = []
    const warn = vi.fn()
    const exit = vi.spyOn(process, 'exit').mockImplementation((() => undefined) as typeof process.exit)

    class IdleClient extends EventEmitter {
      // pg-pool drops a client on release when this is false, so it never sits idle.
      _queryable = true
      _ending = false

      constructor(readonly config: PoolConfig) {
        super()
        clients.push(this)
      }

      connect(callback: (err?: Error) => void): void {
        callback()
      }

      query(
        _text: string,
        valuesOrCallback?: unknown,
        maybeCallback?: (err: Error | null, result: { rows: never[]; rowCount: number }) => void,
      ): void {
        const callback = typeof valuesOrCallback === 'function' ? valuesOrCallback : maybeCallback
        callback?.(null, { rows: [], rowCount: 0 })
      }

      end(callback?: () => void): void {
        this._ending = true
        callback?.()
      }
    }

    const pool = createDatabasePool(
      {
        max: 1,
        idleTimeoutMillis: 0,
        Client: IdleClient as unknown as PoolConfig['Client'],
      },
      { warn },
    )
    try {
      await pool.query('SELECT 1')
      expect(clients).toHaveLength(1)
      expect(clients[0]?.config.keepAlive).toBe(true)
      expect(pool.idleCount).toBe(1)

      const error = new Error('Connection terminated unexpectedly')
      expect(() => {
        clients[0]?.emit('error', error)
      }).not.toThrow()
      expect(warn).toHaveBeenCalledWith({ err: error }, idleClientErrorMessage)
      expect(exit).not.toHaveBeenCalled()
      expect(pool.totalCount).toBe(0)
      expect(pool.idleCount).toBe(0)

      const refreshed = await Promise.race([
        pool.query('SELECT 1'),
        new Promise<never>((_resolve, reject) => {
          setTimeout(() => reject(new Error('timed out waiting for a fresh client')), 500)
        }),
      ])
      expect(refreshed.rowCount).toBe(0)
      expect(clients).toHaveLength(2)
      expect(clients[1]).not.toBe(clients[0])
      expect(clients[1]?.config.keepAlive).toBe(true)
    } finally {
      exit.mockRestore()
      await pool.end()
    }
  })
})
