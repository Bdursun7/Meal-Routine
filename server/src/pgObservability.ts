import { randomUUID } from 'node:crypto'
import type { Pool } from 'pg'
import type { ObservabilityStore } from './observability.js'

const retention = `30 days`

export function createPgObservability(pool: Pool): ObservabilityStore {
  return {
    async insertEvents(accountId, events, now) {
      for (const event of events) {
        await pool.query(
          `INSERT INTO analytics_events (id, account_id, name, properties, occurred_at, received_at)
           VALUES ($1, $2, $3, $4::jsonb, $5, $6)
           ON CONFLICT (id) DO NOTHING`,
          [event.id, accountId, event.name, JSON.stringify(event.properties), event.occurredAt ?? null, now],
        )
      }
      await pool.query(`DELETE FROM analytics_events WHERE received_at < $1::timestamptz - interval '${retention}'`, [now])
    },
    async insertDiagnostics(accountId, reports, now) {
      for (const report of reports) {
        await pool.query(
          `INSERT INTO client_diagnostics (id, account_id, kind, count, exception_type, signal, received_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [randomUUID(), accountId, report.kind, report.count, report.exceptionType ?? null, report.signal ?? null, now],
        )
      }
      await pool.query(`DELETE FROM client_diagnostics WHERE received_at < $1::timestamptz - interval '${retention}'`, [now])
    },
    async erase(accountId) {
      await pool.query(`DELETE FROM analytics_events WHERE account_id = $1`, [accountId])
      await pool.query(`DELETE FROM client_diagnostics WHERE account_id = $1`, [accountId])
    },
  }
}
