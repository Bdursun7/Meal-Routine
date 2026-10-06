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
import { createRateLimiter, type RateLimiter } from './rateLimit.js'
import type { AuthRepository } from './repository.js'
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

const mutationBody = z.object({
  entityType: z.enum(['grocery', 'meal', 'reaction', 'plan', 'preference']),
  entityId: z.string().min(1).max(80),
  operationType: z.enum(['add', 'check', 'replace', 'set', 'upsert', 'update', 'cook']),
  baseRevision: z.number().int().nonnegative(),
  payload: z.record(z.string(), z.unknown()),
})

export interface BuildAppOptions {
  repo: AuthRepository & HouseholdStore & BoardStore
  config: AppConfig
  verifier: IdentityVerifier
  now?: () => Date
  householdNow?: () => Date
  rateLimiter?: RateLimiter
  migration?: MigrationStore
  logger?: boolean
  logStream?: Writable
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
  const migration = createMigrationService(options.migration ?? createMemoryMigration())

  const app = Fastify({
    logger: options.logStream
      ? { level: 'info', stream: options.logStream }
      : (options.logger ?? false),
    logController: new LogController({ disableRequestLogging: true }),
  })

  app.addHook('onRequest', async (request) => {
    if (request.url.startsWith('/v1')) enforceClientVersion(request)
  })

  app.addHook('onSend', async (_request, reply, payload) => {
    reply.header('X-API-Version', config.apiVersion)
    return payload
  })

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof AppError) {
      request.log.warn({ code: error.code }, 'request failed')
      const body: Record<string, unknown> = { ...(error.details ?? {}), error: error.code }
      if (error.existingProviders) body.existingProviders = error.existingProviders
      return reply.code(error.status).send(body)
    }
    const status = statusCode(error)
    if (status === 400) {
      request.log.warn({ code: 'invalid_request' }, 'request failed')
      return reply.code(400).send({ error: 'invalid_request' })
    }
    request.log.error({ code: 'internal' }, 'request failed')
    return reply.code(500).send({ error: 'internal' })
  })

  app.get('/health', async () => ({ ok: true }))

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
    const accountId = await requireAccount(request, config)
    const me = await service.me(accountId)
    return { account: me.account, identities: me.identities }
  })

  app.post('/v1/auth/link', async (request, reply) => {
    enforceRateLimit(request, limiter)
    const accountId = await requireAccount(request, config)
    const body = parse(linkBody, request.body)
    const verified = await verifyForProvider(options.verifier, body.provider, body.identityToken)
    if (body.provider === 'apple') {
      verified.givenName = body.givenName?.trim() || verified.givenName
      verified.familyName = body.familyName?.trim() || verified.familyName
    }
    return reply.send(await service.link(accountId, verified))
  })

  app.delete('/v1/auth/identities/:provider', async (request, reply) => {
    const accountId = await requireAccount(request, config)
    const params = parse(z.object({ provider: z.string().min(1).max(20) }), request.params)
    return reply.send(await service.unlink(accountId, params.provider))
  })

  app.get('/v1/households/current', async (request) => {
    const accountId = await requireAccount(request, config)
    return households.current(accountId)
  })

  app.post('/v1/households', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const body = parse(nameBody, request.body)
    return households.create(accountId, body.name)
  })

  app.get('/v1/households/:householdId', async (request) => {
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    const role = await options.repo.membership(params.householdId, accountId)
    if (!role) throw new AppError('not_found', 404)
    return { id: params.householdId, role }
  })

  app.patch('/v1/households/:householdId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    const body = parse(nameBody, request.body)
    return households.rename(accountId, params.householdId, body.name)
  })

  app.post('/v1/households/:householdId/invites', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    return households.createInvite(accountId, params.householdId)
  })

  app.post('/v1/households/:householdId/invites/:inviteId/resend', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(inviteParams, request.params)
    return households.resendInvite(accountId, params.householdId, params.inviteId)
  })

  app.post('/v1/households/:householdId/invites/:inviteId/cancel', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(inviteParams, request.params)
    return households.cancelInvite(accountId, params.householdId, params.inviteId)
  })

  app.post('/v1/invites/:code/accept', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(codeParams, request.params)
    return households.acceptInvite(accountId, params.code)
  })

  app.post('/v1/invites/:code/reject', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(codeParams, request.params)
    return households.rejectInvite(accountId, params.code)
  })

  app.delete('/v1/households/:householdId/members/:accountId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(memberParams, request.params)
    return households.removeMember(accountId, params.householdId, params.accountId)
  })

  app.post('/v1/households/:householdId/leave', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    return households.leave(accountId, params.householdId)
  })

  app.post('/v1/households/:householdId/transfer', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    const body = parse(transferBody, request.body)
    return households.transfer(accountId, params.householdId, body.accountId)
  })

  app.get('/v1/migration', async (request) => {
    const accountId = await requireAccount(request, config)
    return migration.status(accountId)
  })

  app.post('/v1/migration/upload', async (request) => {
    enforceWriteLimit(request, limiter, 'migration')
    const accountId = await requireAccount(request, config)
    return migration.upload(accountId, parseUpload(request.body))
  })

  app.post('/v1/migration/confirm', async (request) => {
    enforceWriteLimit(request, limiter, 'migration')
    const accountId = await requireAccount(request, config)
    return migration.confirm(accountId)
  })

  app.get('/v1/households/:householdId/board', async (request) => {
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    return board.board(accountId, params.householdId)
  })

  app.get('/v1/households/:householdId/changes', async (request) => {
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    const query = parse(z.object({ cursor: z.coerce.number().int().nonnegative().optional() }), request.query)
    return board.changes(accountId, params.householdId, query.cursor ?? 0)
  })

  app.post('/v1/households/:householdId/mutations', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    const idempotencyKey = headerValue(request.headers['idempotency-key'])
    if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
      throw new AppError('invalid_request', 400)
    }
    const body = parse(mutationBody, request.body)
    return board.mutate(accountId, params.householdId, idempotencyKey, body)
  })

  app.put('/v1/households/:householdId/board', async (request) => {
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    return board.board(accountId, params.householdId)
  })

  app.delete('/v1/households/:householdId', async (request) => {
    enforceWriteLimit(request, limiter, 'household')
    const accountId = await requireAccount(request, config)
    const params = parse(householdParams, request.params)
    return households.deleteHousehold(accountId, params.householdId)
  })

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

async function requireAccount(request: FastifyRequest, config: AppConfig): Promise<string> {
  const header = request.headers.authorization
  if (!header?.startsWith('Bearer ')) throw new AppError('session_expired', 401)
  try {
    const token = await verifyAccessToken(header.slice('Bearer '.length), config.jwtSecret)
    request.accountId = token.accountId
    return token.accountId
  } catch {
    throw new AppError('session_expired', 401)
  }
}

async function assertMember(request: FastifyRequest, options: BuildAppOptions, config: AppConfig): Promise<void> {
  const accountId = await requireAccount(request, config)
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
