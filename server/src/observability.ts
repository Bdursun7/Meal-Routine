import { randomUUID } from 'node:crypto'
import { z } from 'zod'

export const productEventNames = [
  'onboarding_completed',
  'plan_generated',
  'meal_cooked',
  'meal_skipped',
  'meal_vetoed',
  'meal_replaced',
  'quick_save',
  'household_created',
  'household_joined',
  'migration_done',
  'sign_in',
  'invite_sent',
  'invite_accepted',
  'plan_finalized',
  'grocery_item_checked',
  'sync_failed',
  'sync_recovered',
] as const

const forbiddenProperty = /name|email|title|note|url|recipe|slug|token|phone|address|text/

const propertiesSchema = z
  .record(z.string().min(1).max(40), z.string().max(40))
  .refine((value) => Object.keys(value).length <= 8, { message: 'too_many_properties' })
  .refine((value) => Object.keys(value).every((key) => !forbiddenProperty.test(key.toLowerCase())), {
    message: 'forbidden_property',
  })

const eventSchema = z
  .object({
    id: z.string().uuid(),
    name: z.enum(productEventNames),
    properties: propertiesSchema.optional().default({}),
    occurredAt: z.string().datetime({ offset: true }).optional(),
  })
  .strict()

export const analyticsBatchSchema = z
  .object({
    events: z.array(eventSchema).min(1).max(20),
  })
  .strict()

export const diagnosticReportSchema = z
  .object({
    kind: z.enum(['crash', 'hang', 'cpu', 'disk', 'metric']),
    count: z.number().int().min(0).max(1_000),
    exceptionType: z.string().max(40).optional(),
    signal: z.string().max(40).optional(),
  })
  .strict()

export const diagnosticBatchSchema = z
  .object({
    reports: z.array(diagnosticReportSchema).min(1).max(5),
  })
  .strict()

export type AnalyticsEventInput = z.output<typeof eventSchema>
export type DiagnosticReportInput = z.output<typeof diagnosticReportSchema>

export interface StoredEvent {
  id: string
  accountId: string
  name: string
  properties: Record<string, string>
  occurredAt: string | null
  receivedAt: string
}

export interface StoredDiagnostic {
  id: string
  accountId: string
  kind: string
  count: number
  exceptionType: string | null
  signal: string | null
  receivedAt: string
}

export interface ObservabilityStore {
  insertEvents(accountId: string, events: AnalyticsEventInput[], now: Date): Promise<void>
  insertDiagnostics(accountId: string, reports: DiagnosticReportInput[], now: Date): Promise<void>
  erase(accountId: string): Promise<void>
}

export interface MemoryObservability extends ObservabilityStore {
  events(): StoredEvent[]
  diagnostics(): StoredDiagnostic[]
}

const retentionMs = 30 * 24 * 60 * 60 * 1000

export function createMemoryObservability(): MemoryObservability {
  const events: StoredEvent[] = []
  const diagnostics: StoredDiagnostic[] = []

  function purge(now: Date): void {
    const cutoff = now.getTime() - retentionMs
    for (let index = events.length - 1; index >= 0; index -= 1) {
      if (Date.parse(events[index].receivedAt) < cutoff) events.splice(index, 1)
    }
    for (let index = diagnostics.length - 1; index >= 0; index -= 1) {
      if (Date.parse(diagnostics[index].receivedAt) < cutoff) diagnostics.splice(index, 1)
    }
  }

  return {
    async insertEvents(accountId, incoming, now) {
      purge(now)
      for (const event of incoming) {
        if (events.some((row) => row.id === event.id)) continue
        events.push({
          id: event.id,
          accountId,
          name: event.name,
          properties: event.properties,
          occurredAt: event.occurredAt ?? null,
          receivedAt: now.toISOString(),
        })
      }
    },
    async insertDiagnostics(accountId, reports, now) {
      purge(now)
      for (const report of reports) {
        diagnostics.push({
          id: randomUUID(),
          accountId,
          kind: report.kind,
          count: report.count,
          exceptionType: report.exceptionType ?? null,
          signal: report.signal ?? null,
          receivedAt: now.toISOString(),
        })
      }
    },
    async erase(accountId) {
      for (let index = events.length - 1; index >= 0; index -= 1) {
        if (events[index].accountId === accountId) events.splice(index, 1)
      }
      for (let index = diagnostics.length - 1; index >= 0; index -= 1) {
        if (diagnostics[index].accountId === accountId) diagnostics.splice(index, 1)
      }
    },
    events() {
      return events.map((row) => ({ ...row, properties: { ...row.properties } }))
    },
    diagnostics() {
      return diagnostics.map((row) => ({ ...row }))
    },
  }
}

export interface MetricsSnapshot {
  requests: number
  errors: number
  errorRate: number
  latencyMs: { count: number; sum: number; max: number }
  authFailures: number
  syncFailures: number
  migrationFailures: number
  pushFailures: number
  syncRecovered: number
}

export interface Metrics {
  record(input: { path: string; status: number; durationMs: number }): void
  notePushFailure(): void
  noteClientSignal(name: string): void
  snapshot(): MetricsSnapshot
}

export type FailureKind = 'auth' | 'sync' | 'migration' | 'push'

export function classifyFailure(path: string, status: number): FailureKind | null {
  const route = path.split('?')[0]
  if (route.startsWith('/v1/auth') && status === 401) return 'auth'
  if (route.startsWith('/v1/migration') && status >= 400) return 'migration'
  if ((route.includes('/mutations') || route.includes('/changes') || route.endsWith('/board')) && status >= 500) {
    return 'sync'
  }
  if (route.includes('/notifications') && status >= 500) return 'push'
  return null
}

export function createMetrics(): Metrics {
  let requests = 0
  let errors = 0
  let latencyCount = 0
  let latencySum = 0
  let latencyMax = 0
  let authFailures = 0
  let syncFailures = 0
  let migrationFailures = 0
  let pushFailures = 0
  let syncRecovered = 0

  return {
    record(input) {
      const path = input.path.split('?')[0]
      if (path === '/metrics' || path === '/health' || path === '/ready') return
      requests += 1
      const duration = Number.isFinite(input.durationMs) ? Math.max(0, input.durationMs) : 0
      latencyCount += 1
      latencySum += duration
      latencyMax = Math.max(latencyMax, duration)
      if (input.status >= 400) errors += 1
      const kind = classifyFailure(path, input.status)
      if (kind === 'auth') authFailures += 1
      if (kind === 'sync') syncFailures += 1
      if (kind === 'migration') migrationFailures += 1
      if (kind === 'push') pushFailures += 1
    },
    notePushFailure() {
      pushFailures += 1
    },
    noteClientSignal(name) {
      if (name === 'sync_failed') syncFailures += 1
      if (name === 'sync_recovered') syncRecovered += 1
    },
    snapshot() {
      return {
        requests,
        errors,
        errorRate: requests === 0 ? 0 : errors / requests,
        latencyMs: { count: latencyCount, sum: latencySum, max: latencyMax },
        authFailures,
        syncFailures,
        migrationFailures,
        pushFailures,
        syncRecovered,
      }
    },
  }
}

export function allowsMetrics(ip: string, authorization: string | undefined, metricsToken: string): boolean {
  const local = ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1'
  if (local) return true
  if (!metricsToken) return false
  return authorization === `Bearer ${metricsToken}`
}

export interface ErrorReporter {
  capture(error: unknown, context: { requestId: string; path: string }): void
}

export function parseSentryDsn(dsn: string): { storeUrl: string } | null {
  if (!dsn.trim()) return null
  let url: URL
  try {
    url = new URL(dsn.trim())
  } catch {
    return null
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null
  const project = url.pathname.replace(/^\//, '')
  if (!project || !url.username) return null
  const key = decodeURIComponent(url.username)
  return { storeUrl: `${url.protocol}//${url.host}/api/${project}/store/?sentry_key=${encodeURIComponent(key)}` }
}

export function createErrorReporter(
  dsn: string,
  send?: (url: string, body: string) => void,
): ErrorReporter {
  const target = parseSentryDsn(dsn)
  if (!target) return { capture() {} }
  const deliver =
    send ??
    ((url: string, body: string) => {
      void fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
      }).catch(() => {})
    })
  return {
    capture(error, context) {
      const message = error instanceof Error ? error.message : 'internal'
      const body = JSON.stringify({
        message: message.slice(0, 200),
        requestId: context.requestId,
        path: context.path.split('?')[0],
      })
      deliver(target.storeUrl, body)
    },
  }
}
