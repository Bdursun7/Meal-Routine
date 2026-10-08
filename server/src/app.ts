import type { Writable } from 'node:stream'
import Fastify, { LogController, type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify'
import { z } from 'zod'
import { createAuthService, type AuthService, type VerifiedIdentity } from './authService.js'
import type { AppConfig } from './config.js'
import { AppError } from './errors.js'
import { createBoardService } from './boardService.js'
import type { BoardStore } from './boardTypes.js'
import { createHouseholdService } from './householdService.js'
import type { HouseholdStore } from './householdTypes.js'
import type { IdentityVerifier } from './jwks.js'
import { redactSensitive } from './log.js'
import { createMemoryMigration } from './memoryMigration.js'
import { createMigrationService, parseUpload, type MigrationStore } from './migrationService.js'
import { createPrivacyService } from './privacyService.js'
import {
  createLogSender,
  createMemoryNotificationStore,
  createNotificationService,
  kindForMutation,
  notificationKinds,
  type NotificationKind,
  type NotificationStore,
  type PushSender,
} from './notifications.js'
import {
  allowsMetrics,
  analyticsBatchSchema,
  createErrorReporter,
  createMemoryObservability,
  createMetrics,
  diagnosticBatchSchema,
  type ErrorReporter,
  type Metrics,
  type ObservabilityStore,
} from './observability.js'
import { createRateLimiter, type RateLimiter } from './rateLimit.js'
import type { AuthRepository } from './repository.js'
import { createPantryService, pantryRecovery, type PantryService } from './pantryService.js'
import { pantryTimestamp, type PantryStore } from './pantryTypes.js'
import { verifyAccessToken } from './tokens.js'

const appleBody = z.object({
  identityToken: z.string().min(1).max(20_000),
  givenName: z.string().max(80).optional(),
  familyName: z.string().max(80).optional(),
})

const googleBody = z.object({
  identityToken: z.string().min(1).max(20_000),
})

const refreshBody = z.object({
  refreshToken: z.string().min(10).max(500),
})

const devBody = z.object({
  subject: z.string().min(3).max(200),
  displayName: z.string().max(80).optional(),
})

const linkBody = z.object({
  provider: z.enum(['apple', 'google']),
  identityToken: z.string().min(1).max(20_000),
  givenName: z.string().max(80).optional(),
  familyName: z.string().max(80).optional(),
})

const householdParams = z.object({
  householdId: z.string().uuid(),
})

const inviteParams = householdParams.extend({
  inviteId: z.string().uuid(),
})

const memberParams = householdParams.extend({
  accountId: z.string().uuid(),
})

const nameBody = z.object({
  name: z.string().min(1).max(80),
})

const transferBody = z.object({
  accountId: z.string().uuid(),
})

const codeParams = z.object({
  code: z.string().min(1).max(32),
})

const preferenceBody = z.object({
  masterEnabled: z.boolean(),
  invitesEnabled: z.boolean(),
  weeklyPlanEnabled: z.boolean(),
  mealVetoEnabled: z.boolean(),
  mealReplacementEnabled: z.boolean(),
  planFinalizedEnabled: z.boolean(),
})

const tokenBody = z.object({
  token: z.string().min(8).max(400),
  platform: z.enum(['ios', 'android']),
})

const tokenDeleteBody = z.object({
  token: z.string().min(8).max(400),
})

const eventBody = z.object({
  kind: z.enum(notificationKinds),
  mealId: z.string().max(80).optional(),
  inviteCode: z.string().max(12).optional(),
})

const mutationBody = z.object({
  entityType: z.enum(['grocery', 'meal', 'reaction', 'plan', 'preference']),
  entityId: z.string().min(1).max(80),
  operationType: z.enum(['add', 'check', 'replace', 'set', 'upsert', 'update', 'cook']),
  baseRevision: z.number().int().nonnegative(),
  payload: z.record(z.string().max(80), z.unknown()).refine((value) => JSON.stringify(value).length <= 16_000),
})

export interface BuildAppOptions {
  repo: AuthRepository & HouseholdStore & BoardStore & PantryStore
  config: AppConfig
  verifier: IdentityVerifier
  now?: () => Date
  householdNow?: () => Date
  rateLimiter?: RateLimiter
  migration?: MigrationStore
  notifications?: NotificationStore
  sender?: PushSender
  logger?: boolean
  logStream?: Writable
  bodyLimit?: number
  readiness?: () => Promise<boolean>
  observability?: ObservabilityStore
  errorReporter?: ErrorReporter
  metrics?: Metrics
}

declare module 'fastify' {
  interface FastifyRequest {
    accountId?: string
  }
}

export function buildApp(options: BuildAppOptions): FastifyInstance {
  const config = options.config
  const service: AuthService = createAuthService({
    repo: options.repo,
    config,
    now: options.now,
  })
  const limiter =
    options.rateLimiter ??
    createRateLimiter({ windowMs: config.rateLimitWindowMs, max: config.rateLimitMax })
  const households = createHouseholdService(options.repo, options.householdNow ?? options.now ?? (() => new Date()))
  const board = createBoardService(options.repo, options.repo, options.householdNow ?? options.now ?? (() => new Date()))
  const pantry = createPantryService(options.repo, options.repo)
  const migrationStore = options.migration ?? createMemoryMigration()
  const migration = createMigrationService(migrationStore)
  const clock = options.now ?? (() => new Date())
  const pushSender = options.sender ?? createLogSender()
  const notificationStore = options.notifications ?? createMemoryNotificationStore()
  const notifications = createNotificationService(notificationStore, pushSender, clock)
  const privacy = createPrivacyService({
    repo: options.repo,
    households,
    migration: migrationStore,
    notifications: notificationStore,
    pantry: options.repo,
    now: clock,
  })
  const observability = options.observability ?? createMemoryObservability()
  const metrics = options.metrics ?? createMetrics()
  const reporter = options.errorReporter ?? createErrorReporter(config.sentryDsn)

  const app = Fastify({
    logger: options.logStream
      ? { level: 'info', stream: options.logStream }
      : (options.logger ?? false),
    logController: new LogController({ disableRequestLogging: true }),
    bodyLimit: options.bodyLimit ?? 1_048_576,
  })

  app.addHook('onRequest', async (request, reply) => {
    reply.header('X-Request-Id', request.id)
    if (request.url.startsWith('/v1')) enforceClientVersion(request)
  })

  app.addHook('onResponse', async (request, reply) => {
    const path = request.url.split('?')[0]
    metrics.record({ path, status: reply.statusCode, durationMs: Number(reply.elapsedTime) || 0 })
    if (options.logger || options.logStream) {
      request.log.info(
        {
          requestId: request.id,
          method: request.method,
          path,
          status: reply.statusCode,
          durationMs: Math.round(Number(reply.elapsedTime) || 0),
        },
        'request',
      )
    }
  })

  app.addHook('onSend', async (request, reply, payload) => {
    reply.header('X-API-Version', config.apiVersion)
    reply.header('X-Content-Type-Options', 'nosniff')
    reply.header('Referrer-Policy', 'no-referrer')
    reply.header('X-Frame-Options', 'DENY')
    reply.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
    reply.header('Cache-Control', 'no-store')
    const origin = headerValue(request.headers.origin)
    if (config.corsOrigin && origin === config.corsOrigin) {
      reply.header('Access-Control-Allow-Origin', config.corsOrigin)
      reply.header('Vary', 'Origin')
      reply.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Client-API-Version, Idempotency-Key')
      reply.header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS')
    }
    return payload
  })

  app.setErrorHandler((error, request, reply) => {
    const pantryRoute = isPantryRoute(request.url)
    if (error instanceof AppError) {
      request.log.warn({ code: error.code }, 'request failed')
      const body: Record<string, unknown> = { ...(error.details ?? {}), error: error.code }
      if (error.existingProviders) body.existingProviders = error.existingProviders
      const recovery = pantryRoute ? pantryRecovery(error.code) : undefined
      if (recovery) body.recovery = recovery
      return reply.code(error.status).send(body)
    }
    const status = statusCode(error)
    if (status === 400 || status === 413) {
      request.log.warn({ code: 'invalid_request' }, 'request failed')
      return reply.code(status).send(pantryRoute ? { error: 'invalid_request', recovery: 'fix-input' } : { error: 'invalid_request' })
    }
    request.log.error({ code: 'internal', requestId: request.id }, 'request failed')
    reporter.capture(error, { requestId: request.id, path: request.url })
    return reply.code(500).send({ error: 'internal' })
  })

  app.options('*', async (_request, reply) => reply.code(204).send())

  app.get('/health', async () => ({ ok: true }))

  app.get('/ready', async (_request, reply) => {
    const probe = options.readiness ?? (async () => true)
    try {
      const ok = await probe()
      if (!ok) return reply.code(503).send({ ok: false })
      return { ok: true }
    } catch {
      return reply.code(503).send({ ok: false })
    }
  })

  app.get('/metrics', async (request) => {
    const authorization = headerValue(request.headers.authorization)
    if (!allowsMetrics(request.ip, authorization || undefined, config.metricsToken)) {
      throw new AppError('not_found', 404)
    }
    return metrics.snapshot()
  })

  app.get('/v1/meta', async () => ({
    apiVersion: 'v1',
    schemaVersion: 1,
    minClientApiVersion: 'v1',
  }))

  app.post('/v1/auth/apple', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const body = parse(appleBody, request.body)
    const verified = await options.verifier.verifyApple(body.identityToken)
    verified.givenName = body.givenName?.trim() || verified.givenName
    verified.familyName = body.familyName?.trim() || verified.familyName
    return sendSignIn(reply, await service.signInWithIdentity(verified))
  })

  app.post('/v1/auth/google', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const body = parse(googleBody, request.body)
    const verified = await options.verifier.verifyGoogle(body.identityToken)
    return sendSignIn(reply, await service.signInWithIdentity(verified))
  })

  app.post('/v1/auth/refresh', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const body = parse(refreshBody, request.body)
    return reply.send(await service.refresh(body.refreshToken))
  })

  app.post('/v1/auth/logout', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const body = parse(refreshBody, request.body)
    await service.logout(body.refreshToken)
    return reply.code(204).send()
  })

  app.post('/v1/auth/dev', async (request, reply) => {
    enforceRateLimit(request, limiter)
    if (config.nodeEnv !== 'development') throw new AppError('not_found', 404)
    const body = parse(devBody, request.body)
    const session = await service.signInDev({
      subject: body.subject,
      displayName: body.displayName?.trim() || 'Yerel test',
    })
    return reply.send(session)
  })

  app.get('/v1/auth/me', async (request) => {
    const accountId = await requireAccount(request, options)
    const me = await service.me(accountId)
    return { account: me.account, identities: me.identities }
  })

  app.get('/v1/account/export', async (request) => {
    enforceWriteLimit(request, limiter, 'auth')
    const accountId = await requireAccount(request, options)
    return privacy.exportAccount(accountId)
  })

  app.delete('/v1/account', async (request) => {
    enforceWriteLimit(request, limiter, 'auth')
    const accountId = await requireAccount(request, options)
    const result = await privacy.deleteAccount(accountId)
    await observability.erase(accountId)
    return result
  })

  app.post('/v1/analytics/events', async (request) => {
    enforceWriteLimit(request, limiter, 'analytics')
    const accountId = await requireAccount(request, options)
    const body = parse(analyticsBatchSchema, request.body)
    const events = body.events.map((event) => ({
      id: event.id,
      name: event.name,
      properties: event.properties ?? {},
      occurredAt: event.occurredAt,
    }))
    await observability.insertEvents(accountId, events, clock())
    for (const event of events) metrics.noteClientSignal(event.name)
    return { accepted: body.events.length }
  })

  app.post('/v1/diagnostics', async (request) => {
    enforceWriteLimit(request, limiter, 'analytics')
    const accountId = await requireAccount(request, options)
    const body = parse(diagnosticBatchSchema, request.body)
    await observability.insertDiagnostics(accountId, body.reports, clock())
    return { accepted: body.reports.length }
  })

  app.post('/v1/auth/link', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const accountId = await requireAccount(request, options)
    const body = parse(linkBody, request.body)
    const verified = await verifyForProvider(options.verifier, body.provider, body.identityToken)
    if (body.provider === 'apple') {
      verified.givenName = body.givenName?.trim() || verified.givenName
      verified.familyName = body.familyName?.trim() || verified.familyName
    }
    return reply.send(await service.link(accountId, verified))
  })

  app.delete('/v1/auth/identities/:provider', async (request, reply) => {
    const accountId = await requireAccount(request, options)
    const params = parse(z.object({ provider: z.string().min(1).max(20) }), request.params)
    return reply.send(await service.unlink(accountId, params.provider))
  })

  app.get('/v1/households/current', async (request) => {
    const accountId = await requireAccount(request, options)
    return households.current(accountId)
  })

  app.post('/v1/households', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const body = parse(nameBody, request.body)
    return households.create(accountId, body.name)
  })

  app.get('/v1/households/:householdId', async (request) => {
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const role = await options.repo.membership(params.householdId, accountId)
    if (!role) throw new AppError('not_found', 404)
    return { id: params.householdId, role }
  })

  app.patch('/v1/households/:householdId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const body = parse(nameBody, request.body)
    return households.rename(accountId, params.householdId, body.name)
  })

  app.post('/v1/households/:householdId/invites', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const created = await households.createInvite(accountId, params.householdId)
    const code = created.household?.invites[0]?.code ?? ''
    await notifyOthers(options.repo, notifications, metrics, accountId, params.householdId, 'invite', '', code)
    return created
  })

  app.post('/v1/households/:householdId/invites/:inviteId/resend', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(inviteParams, request.params)
    return households.resendInvite(accountId, params.householdId, params.inviteId)
  })

  app.post('/v1/households/:householdId/invites/:inviteId/cancel', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(inviteParams, request.params)
    return households.cancelInvite(accountId, params.householdId, params.inviteId)
  })

  app.post('/v1/invites/:code/accept', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(codeParams, request.params)
    return households.acceptInvite(accountId, params.code)
  })

  app.post('/v1/invites/:code/reject', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(codeParams, request.params)
    return households.rejectInvite(accountId, params.code)
  })

  app.delete('/v1/households/:householdId/members/:accountId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(memberParams, request.params)
    return households.removeMember(accountId, params.householdId, params.accountId)
  })

  app.post('/v1/households/:householdId/leave', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const result = await households.leave(accountId, params.householdId)
    const remaining = await options.repo.transaction(async (tx) => tx.household(params.householdId))
    if (!remaining || remaining.deletedAt) await pantry.deleteHousehold(params.householdId)
    return result
  })

  app.post('/v1/households/:householdId/transfer', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const body = parse(transferBody, request.body)
    return households.transfer(accountId, params.householdId, body.accountId)
  })

  app.get('/v1/migration', async (request) => {
    const accountId = await requireAccount(request, options)
    return migration.status(accountId)
  })

  app.post('/v1/migration/upload', async (request) => {
    enforceWriteLimit(request, limiter, 'migration')
    const accountId = await requireAccount(request, options)
    return migration.upload(accountId, parseUpload(request.body))
  })

  app.post('/v1/migration/confirm', async (request) => {
    enforceWriteLimit(request, limiter, 'migration')
    const accountId = await requireAccount(request, options)
    return migration.confirm(accountId)
  })

  app.get('/v1/households/:householdId/board', async (request) => {
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    return board.board(accountId, params.householdId)
  })

  app.get('/v1/households/:householdId/changes', async (request) => {
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const query = parse(z.object({ cursor: z.coerce.number().int().nonnegative().optional() }), request.query)
    return board.changes(accountId, params.householdId, query.cursor ?? 0)
  })

  app.post('/v1/households/:householdId/mutations', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const idempotencyKey = headerValue(request.headers['idempotency-key'])
    if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
      throw new AppError('invalid_request', 400)
    }
    const body = parse(mutationBody, request.body)
    const result = await board.mutate(accountId, params.householdId, idempotencyKey, body)
    const event = kindForMutation(body)
    if (event) await notifyOthers(options.repo, notifications, metrics, accountId, params.householdId, event.kind, event.mealId, '')
    return result
  })

  app.get('/v1/notifications/preferences', async (request) => {
    const accountId = await requireAccount(request, options)
    return notifications.preferences(accountId)
  })

  app.put('/v1/notifications/preferences', async (request) => {
    enforceWriteLimit(request, limiter, 'notifications')
    const accountId = await requireAccount(request, options)
    const body = parse(preferenceBody, request.body)
    await notifications.savePreferences(accountId, body)
    return body
  })

  app.get('/v1/notifications/tokens', async (request) => {
    const accountId = await requireAccount(request, options)
    return { tokens: await notifications.listTokens(accountId) }
  })

  app.post('/v1/notifications/tokens', async (request) => {
    enforceWriteLimit(request, limiter, 'notifications')
    const accountId = await requireAccount(request, options)
    const body = parse(tokenBody, request.body)
    await notifications.registerToken(accountId, body.token, body.platform)
    return { ok: true }
  })

  app.delete('/v1/notifications/tokens', async (request) => {
    const accountId = await requireAccount(request, options)
    const body = parse(tokenDeleteBody, request.body)
    await notifications.unregisterToken(accountId, body.token)
    return { ok: true }
  })

  app.post('/v1/households/:householdId/notifications', async (request) => {
    enforceWriteLimit(request, limiter, 'notifications')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const role = await options.repo.membership(params.householdId, accountId)
    if (!role) throw new AppError('not_found', 404)
    const body = parse(eventBody, request.body)
    await notifyOthers(options.repo, notifications, metrics, accountId, params.householdId, body.kind, body.mealId ?? '', body.inviteCode ?? '')
    return { batches: await notifications.listBatches(accountId) }
  })

  app.get('/v1/notifications/outbox', async (request) => {
    const accountId = await requireAccount(request, options)
    return { batches: await notifications.listBatches(accountId) }
  })

  app.post('/v1/notifications/dispatch', async (request) => {
    await requireAccount(request, options)
    return { sent: await notifications.dispatch() }
  })

  app.put('/v1/households/:householdId/board', async (request) => {
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    return board.board(accountId, params.householdId)
  })

  app.delete('/v1/households/:householdId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, options)
    const params = parse(householdParams, request.params)
    const result = await households.deleteHousehold(accountId, params.householdId)
    await pantry.deleteHousehold(params.householdId)
    return result
  })

  registerPantryRoutes(app, options, pantry, limiter, clock)

  return app
}

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value)
  if (!result.success) throw new AppError('invalid_request', 400)
  return result.data
}

function headerValue(value: string | string[] | undefined): string {
  const raw = Array.isArray(value) ? value[0] : value
  return raw?.trim() ?? ''
}

function enforceRateLimit(request: FastifyRequest, limiter: RateLimiter): void {
  enforceWriteLimit(request, limiter, 'auth')
}

function enforceWriteLimit(request: FastifyRequest, limiter: RateLimiter, scope: string): void {
  if (!limiter.allow(`${request.ip}:${scope}`)) throw new AppError('rate_limited', 429)
}

function enforceClientVersion(request: FastifyRequest): void {
  const header = request.headers['x-client-api-version']
  if (header === undefined) return
  const value = Array.isArray(header) ? header[0] : header
  if (value !== '1' && value !== 'v1') throw new AppError('unsupported_api_version', 406)
}

async function notifyOthers(
  repo: BuildAppOptions['repo'],
  notifications: ReturnType<typeof createNotificationService>,
  metrics: Metrics,
  actorId: string,
  householdId: string,
  kind: NotificationKind,
  mealId: string,
  inviteCode: string,
) {
  try {
    const members = await repo.transaction(async (tx) => tx.members(householdId))
    for (const member of members) {
      if (member.accountId === actorId) continue
      await notifications.enqueue(member.accountId, householdId, kind, mealId, inviteCode)
    }
  } catch {
    metrics.notePushFailure()
  }
}

async function requireAccount(request: FastifyRequest, options: BuildAppOptions): Promise<string> {
  const header = request.headers.authorization
  if (!header?.startsWith('Bearer ')) throw new AppError('session_expired', 401)
  try {
    const token = await verifyAccessToken(header.slice('Bearer '.length), options.config.jwtSecret)
    const account = await options.repo.getAccount(token.accountId)
    if (!account) throw new AppError('session_expired', 401)
    request.accountId = token.accountId
    return token.accountId
  } catch (error) {
    if (error instanceof AppError) throw error
    throw new AppError('session_expired', 401)
  }
}

async function assertMember(request: FastifyRequest, options: BuildAppOptions): Promise<void> {
  const accountId = await requireAccount(request, options)
  const params = parse(householdParams, request.params)
  const role = await options.repo.membership(params.householdId, accountId)
  if (!role) throw new AppError('not_found', 404)
}

async function verifyForProvider(
  verifier: IdentityVerifier,
  provider: 'apple' | 'google',
  token: string,
): Promise<VerifiedIdentity> {
  if (provider === 'apple') return verifier.verifyApple(token)
  return verifier.verifyGoogle(token)
}

function sendSignIn(reply: FastifyReply, result: Awaited<ReturnType<AuthService['signInWithIdentity']>>) {
  if (result.kind === 'link_required') {
    return reply.code(409).send({
      error: 'link_required',
      existingProviders: result.existingProviders,
    })
  }
  return reply.send(result.session)
}

function statusCode(error: unknown): number | undefined {
  if (error && typeof error === 'object' && 'statusCode' in error) {
    const code = (error as { statusCode?: number }).statusCode
    return typeof code === 'number' ? code : undefined
  }
  return undefined
}

export function loggedBody(body: unknown): unknown {
  return redactSensitive(body)
}

const pantryLocation = z.enum(['pantry', 'refrigerator', 'freezer', 'other'])
const pantryDateType = z.enum(['bestBefore', 'useBy'])
const pantryItemFields = {
  ingredientId: z.string().min(1).max(120),
  displayName: z.string().min(1).max(160),
  quantity: z.number().nonnegative(),
  unit: z.string().min(1).max(40),
  location: pantryLocation,
  minimumQuantity: z.number().nonnegative().nullable().optional(),
  dateType: pantryDateType.nullable().optional(),
  dateValue: z.string().max(10).nullable().optional(),
  confirmSeparate: z.boolean().optional(),
}
// Strict: a pre-gate client that still sends `bestBefore` is rejected instead of losing the date.
const pantryCreateBody = z.object({ id: z.string().uuid().optional(), ...pantryItemFields }).strict()
const pantryPatchBody = z.object(pantryItemFields).partial().strict()
const pantryVersionQuery = z.object({
  baseVersion: z.coerce.number().int().positive().optional(),
  baseRevision: z.coerce.number().int().positive().optional(),
})
const pantryReconcileBody = z.object({
  operation: z.enum(['compute-missing', 'consume', 'restock']),
  confirmSeparate: z.boolean().optional(),
  lines: z.array(z.object({
    ingredientId: z.string().min(1).max(160),
    displayName: z.string().min(1).max(160).optional(),
    quantity: z.number().nonnegative(),
    unit: z.string().min(1).max(40),
    checked: z.boolean().optional(),
    location: pantryLocation.optional(),
  }).strict()).min(1).max(200),
}).strict()
const ingredientQuery = z.object({
  householdId: z.string().uuid().optional(),
  q: z.string().max(80).optional(),
  limit: z.coerce.number().int().min(1).max(1000).optional(),
})
const ingredientBody = z.object({
  id: z.string().min(1).max(120),
  displayName: z.string().min(1).max(160),
}).strict()

function isPantryRoute(url: string): boolean {
  const path = url.split('?')[0] ?? ''
  return path.startsWith('/v1/ingredients') || /^\/v1\/households\/[^/]+\/(pantry|ingredients)(\/|$)/.test(path)
}

function registerPantryRoutes(app: FastifyInstance, options: BuildAppOptions, pantry: PantryService, limiter: RateLimiter, clock: () => Date): void {
  const itemParams = householdParams.extend({ itemId: z.string().uuid().transform((value) => value.toLowerCase()) })
  const idempotencyKey = (request: FastifyRequest) => headerValue(request.headers['idempotency-key'])
  const baseVersion = (request: FastifyRequest) => {
    const query = parse(pantryVersionQuery, request.query)
    return query.baseVersion ?? query.baseRevision
  }

  app.get('/v1/ingredients', async (request) => {
    const accountId = await requireAccount(request, options)
    const query = parse(ingredientQuery, request.query)
    const rows = await pantry.ingredients(accountId, query.householdId ?? null, query.q?.trim() ?? '', query.limit ?? 1000)
    return {
      version: 1,
      ingredients: rows.map((row) => ({
        id: row.id,
        displayName: row.displayName,
        synonyms: row.synonyms,
        sourceIds: row.sourceIds,
        scope: row.householdId ? 'household' : 'dictionary',
      })),
    }
  })

  app.post('/v1/households/:householdId/ingredients', async (request) => {
    enforceWriteLimit(request, limiter, 'pantry')
    const accountId = await requireAccount(request, options)
    const { householdId } = parse(householdParams, request.params)
    const body = parse(ingredientBody, request.body)
    const row = await pantry.registerIngredient(accountId, householdId, body, idempotencyKey(request), clock())
    return { id: row.id, displayName: row.displayName, synonyms: row.synonyms, sourceIds: row.sourceIds, scope: 'household' }
  })

  app.get('/v1/households/:householdId/pantry', async (request) => {
    const accountId = await requireAccount(request, options)
    const { householdId } = parse(householdParams, request.params)
    return { items: await pantry.list(accountId, householdId), serverTime: pantryTimestamp(clock()) }
  })

  app.post('/v1/households/:householdId/pantry/items', async (request) => {
    enforceWriteLimit(request, limiter, 'pantry')
    const accountId = await requireAccount(request, options)
    const { householdId } = parse(householdParams, request.params)
    const { confirmSeparate, ...body } = parse(pantryCreateBody, request.body)
    return pantry.create(accountId, householdId, {
      ...(body.id ? { id: body.id } : {}),
      ingredientId: body.ingredientId,
      displayName: body.displayName,
      quantity: body.quantity,
      unit: body.unit,
      location: body.location,
      minimumQuantity: body.minimumQuantity ?? null,
      dateType: body.dateType ?? null,
      dateValue: body.dateValue ?? null,
    }, idempotencyKey(request), clock(), { confirmSeparate: confirmSeparate === true })
  })

  app.post('/v1/households/:householdId/pantry/reconcile-grocery', async (request) => {
    enforceWriteLimit(request, limiter, 'pantry')
    const accountId = await requireAccount(request, options)
    const { householdId } = parse(householdParams, request.params)
    const body = parse(pantryReconcileBody, request.body)
    return pantry.reconcile(accountId, householdId, { operation: body.operation, lines: body.lines, confirmSeparate: body.confirmSeparate === true }, idempotencyKey(request), clock())
  })

  app.patch('/v1/households/:householdId/pantry/items/:itemId', async (request) => {
    enforceWriteLimit(request, limiter, 'pantry')
    const accountId = await requireAccount(request, options)
    const params = parse(itemParams, request.params)
    const { confirmSeparate, ...patch } = parse(pantryPatchBody, request.body)
    return pantry.update(accountId, params.householdId, params.itemId, patch, baseVersion(request), idempotencyKey(request), clock(), { confirmSeparate: confirmSeparate === true })
  })

  app.delete('/v1/households/:householdId/pantry/items/:itemId', async (request) => {
    enforceWriteLimit(request, limiter, 'pantry')
    const accountId = await requireAccount(request, options)
    const params = parse(itemParams, request.params)
    return pantry.remove(accountId, params.householdId, params.itemId, baseVersion(request), idempotencyKey(request), clock())
  })
}
