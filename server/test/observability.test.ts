import { Writable } from 'node:stream'
import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { assertRuntimeConfig, loadConfig } from '../src/config.js'
import {
  classifyFailure,
  createErrorReporter,
  createMemoryObservability,
  createMetrics,
  parseSentryDsn,
  productEventNames,
} from '../src/observability.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'
import type { FastifyInstance } from 'fastify'

const eventId = '11111111-1111-4111-8111-111111111111'
const secondId = '22222222-2222-4222-8222-222222222222'

describe('observability', () => {
  it('serves health without the database and ready only when the probe succeeds', async () => {
    const down = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: testVerifier(),
      readiness: async () => false,
    })
    const health = await down.inject({ method: 'GET', url: '/health' })
    const ready = await down.inject({ method: 'GET', url: '/ready' })
    expect(health.statusCode).toBe(200)
    expect(health.json()).toEqual({ ok: true })
    expect(ready.statusCode).toBe(503)
    expect(ready.json()).toEqual({ ok: false })
    await down.close()

    const up = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const live = await up.inject({ method: 'GET', url: '/ready' })
    expect(live.statusCode).toBe(200)
    expect(live.headers['x-request-id']).toBeTruthy()
    await up.close()
  })

  it('counts requests and keeps metrics on localhost unless a token is set', async () => {
    expect(classifyFailure('/v1/auth/apple', 401)).toBe('auth')
    expect(classifyFailure('/v1/migration/upload', 400)).toBe('migration')
    expect(classifyFailure('/v1/households/x/mutations', 500)).toBe('sync')
    expect(classifyFailure('/v1/notifications/dispatch', 500)).toBe('push')
    expect(classifyFailure('/v1/households/x/board', 404)).toBeNull()

    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const denied = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: { identityToken: 'not-a-token' },
    })
    expect(denied.statusCode).toBe(401)
    const metrics = await app.inject({ method: 'GET', url: '/metrics' })
    expect(metrics.statusCode).toBe(200)
    expect(metrics.json().authFailures).toBeGreaterThanOrEqual(1)
    expect(metrics.json().requests).toBeGreaterThanOrEqual(1)
    expect(metrics.json().errorRate).toBeGreaterThan(0)
    const remote = await app.inject({ method: 'GET', url: '/metrics', remoteAddress: '203.0.113.8' })
    expect(remote.statusCode).toBe(404)
    await app.close()

    const tokened = buildApp({
      repo: memoryRepo(),
      config: testConfig({ metricsToken: 'metrics-secret' }),
      verifier: testVerifier(),
    })
    const locked = await tokened.inject({ method: 'GET', url: '/metrics', remoteAddress: '203.0.113.8' })
    expect(locked.statusCode).toBe(404)
    const opened = await tokened.inject({
      method: 'GET',
      url: '/metrics',
      remoteAddress: '203.0.113.8',
      headers: { authorization: 'Bearer metrics-secret' },
    })
    expect(opened.statusCode).toBe(200)
    await tokened.close()
  })

  it('writes a request id and reports unexpected errors only when a DSN is set', async () => {
    expect(loadConfig({}).sentryDsn).toBe('')
    expect(parseSentryDsn('')).toBeNull()
    expect(() => assertRuntimeConfig(testConfig({
      databaseUrl: 'postgres://local/meal',
      sentryDsn: 'not a dsn',
    }))).toThrow(/SENTRY_DSN/)
    const calls: string[] = []
    const silent = createErrorReporter('', (url, body) => calls.push(url + body))
    silent.capture(new Error('secret-token'), { requestId: '1', path: '/v1/auth/apple' })
    expect(calls).toEqual([])

    const lines: string[] = []
    const stream = new Writable({
      write(chunk, _encoding, callback) {
        lines.push(String(chunk))
        callback()
      },
    })
    const reported: string[] = []
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: {
        async verifyApple() {
          throw new Error('boom')
        },
        async verifyGoogle() {
          throw new Error('boom')
        },
      },
      logStream: stream,
      errorReporter: createErrorReporter('https://public@errors.example/1', (url, body) => {
        reported.push(`${url}\n${body}`)
      }),
    })
    const token = 'super-secret-token-value-xxxx'
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: { identityToken: token, givenName: 'Ada' },
    })
    expect(response.statusCode).toBe(500)
    const blob = lines.join('\n')
    expect(blob).toContain('requestId')
    expect(blob).toContain('/v1/auth/apple')
    expect(blob).not.toContain(token)
    expect(blob).not.toContain('Ada')
    expect(reported).toHaveLength(1)
    expect(reported[0]).toContain('/api/1/store/')
    expect(reported[0]).toContain('boom')
    expect(reported[0]).not.toContain(token)
    await app.close()
  })

  it('stores only the caller events, rejects oversized or personal payloads, and erases them on delete', async () => {
    const observability = createMemoryObservability()
    const metrics = createMetrics()
    let now = new Date()
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: testVerifier(),
      observability,
      metrics,
      now: () => now,
      sender: {
        name: 'fail',
        async send() {
          throw new Error('push down')
        },
      },
    })
    const ada = await signIn(app, 'ada-obs')
    const bea = await signIn(app, 'bea-obs')
    const anonymous = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      payload: { events: [sampleEvent(eventId, 'plan_generated')] },
    })
    expect(anonymous.statusCode).toBe(401)

    const spoofed = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: ada.auth,
      payload: { accountId: bea.id, events: [sampleEvent(eventId, 'plan_generated')] },
    })
    expect(spoofed.statusCode).toBe(400)
    expect(observability.events()).toEqual([])

    const titled = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: ada.auth,
      payload: {
        events: [{
          ...sampleEvent(eventId, 'quick_save'),
          properties: { title: 'Menemen' },
        }],
      },
    })
    expect(titled.statusCode).toBe(400)

    const huge = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: ada.auth,
      payload: {
        events: Array.from({ length: 21 }, (_, index) => sampleEvent(idFor(index), 'meal_cooked')),
      },
    })
    expect(huge.statusCode).toBe(400)

    const accepted = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: ada.auth,
      payload: {
        events: [
          sampleEvent(eventId, 'plan_generated', { source: 'week' }),
          sampleEvent(secondId, 'sync_failed'),
        ],
      },
    })
    expect(accepted.statusCode).toBe(200)
    expect(accepted.json()).toEqual({ accepted: 2 })
    const again = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: ada.auth,
      payload: { events: [sampleEvent(eventId, 'plan_generated')] },
    })
    expect(again.statusCode).toBe(200)
    const stored = observability.events()
    expect(stored).toHaveLength(2)
    expect(stored.every((row) => row.accountId === ada.id)).toBe(true)
    expect(JSON.stringify(stored)).not.toContain('Menemen')
    expect(metrics.snapshot().syncFailures).toBeGreaterThanOrEqual(1)

    const beaEvent = await app.inject({
      method: 'POST',
      url: '/v1/analytics/events',
      headers: bea.auth,
      payload: { events: [sampleEvent('33333333-3333-4333-8333-333333333333', 'household_joined')] },
    })
    expect(beaEvent.statusCode).toBe(200)
    expect(observability.events().find((row) => row.name === 'household_joined')?.accountId).toBe(bea.id)

    const diagnostic = await app.inject({
      method: 'POST',
      url: '/v1/diagnostics',
      headers: ada.auth,
      payload: { reports: [{ kind: 'crash', count: 1, exceptionType: 'SIGSEGV', stack: 'frame' }] },
    })
    expect(diagnostic.statusCode).toBe(400)
    const savedDiagnostic = await app.inject({
      method: 'POST',
      url: '/v1/diagnostics',
      headers: ada.auth,
      payload: { reports: [{ kind: 'crash', count: 1, exceptionType: 'SIGSEGV' }] },
    })
    expect(savedDiagnostic.statusCode).toBe(200)
    expect(observability.diagnostics()).toEqual([
      expect.objectContaining({ accountId: ada.id, kind: 'crash', count: 1, exceptionType: 'SIGSEGV' }),
    ])

    const brokenMigration = await app.inject({
      method: 'POST',
      url: '/v1/migration/upload',
      headers: ada.auth,
      payload: { recipes: 'nope' },
    })
    expect(brokenMigration.statusCode).toBe(400)
    expect(metrics.snapshot().migrationFailures).toBeGreaterThanOrEqual(1)

    const household = await createHousehold(app, ada.auth)
    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const code = invited.json().household.invites[0].code as string
    const joined = await app.inject({ method: 'POST', url: `/v1/invites/${code}/accept`, headers: bea.auth })
    expect(joined.statusCode).toBe(200)
    const registered = await app.inject({
      method: 'POST',
      url: '/v1/notifications/tokens',
      headers: bea.auth,
      payload: { token: 'bea-device-token', platform: 'ios' },
    })
    expect(registered.statusCode).toBe(200)
    const pushed = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/notifications`,
      headers: ada.auth,
      payload: { kind: 'invite' },
    })
    expect(pushed.statusCode).toBe(200)
    now = new Date(now.getTime() + 3 * 60 * 1000)
    const dispatched = await app.inject({
      method: 'POST',
      url: '/v1/notifications/dispatch',
      headers: ada.auth,
    })
    expect(dispatched.statusCode).toBe(500)
    expect(metrics.snapshot().pushFailures).toBeGreaterThanOrEqual(1)

    const removed = await app.inject({ method: 'DELETE', url: '/v1/account', headers: ada.auth })
    expect(removed.statusCode).toBe(200)
    expect(observability.events().some((row) => row.accountId === ada.id)).toBe(false)
    expect(observability.diagnostics().some((row) => row.accountId === ada.id)).toBe(false)
    expect(observability.events().some((row) => row.accountId === bea.id)).toBe(true)
    await app.close()
  })

  it('drops events older than the retention window', async () => {
    const store = createMemoryObservability()
    await store.insertEvents('acct', [sampleEvent(eventId, 'sign_in')], new Date('2020-01-01T00:00:00Z'))
    await store.insertEvents('acct', [sampleEvent(secondId, 'meal_cooked')], new Date('2020-03-15T00:00:00Z'))
    expect(store.events().map((row) => row.id)).toEqual([secondId])
  })
})

function sampleEvent(
  id: string,
  name: (typeof productEventNames)[number],
  properties: Record<string, string> = {},
) {
  return {
    id,
    name,
    properties,
    occurredAt: '2024-06-01T00:00:00Z',
  }
}

function idFor(index: number): string {
  const tail = index.toString(16).padStart(12, '0')
  return `44444444-4444-4444-8444-${tail}`
}

async function signIn(app: FastifyInstance, subject: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: { identityToken: identityToken({ subject, givenName: subject, familyName: '' }) },
  })
  expect(response.statusCode).toBe(200)
  const body = response.json()
  return {
    id: body.account.id as string,
    auth: { authorization: `Bearer ${body.accessToken as string}` },
  }
}

async function createHousehold(app: FastifyInstance, auth: { authorization: string }) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/households',
    headers: auth,
    payload: { name: 'Ev' },
  })
  expect(response.statusCode).toBe(200)
  return response.json().household as { id: string }
}
