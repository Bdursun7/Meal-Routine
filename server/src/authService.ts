import { randomUUID } from 'node:crypto'
import type { AppConfig } from './config.js'
import { AppError } from './errors.js'
import type { AccountRow, AuthRepository, IdentityRow, ProviderName } from './repository.js'
import { hashToken, newRefreshToken, signAccessToken } from './tokens.js'
import { accountRegional, defaultUserSettings, type UserRegionalSettings } from './regional.js'

export interface VerifiedIdentity {
  provider: 'apple' | 'google'
  subject: string
  email: string | null
  emailVerified: boolean
  isPrivateRelay: boolean
  givenName: string
  familyName: string
}

export interface PublicIdentity {
  provider: string
  email: string | null
  isPrivateRelay: boolean
}

export interface PublicAccount {
  id: string
  displayName: string
  givenName: string
  familyName: string
}

export interface PublicSession {
  accessToken: string
  refreshToken: string
  expiresIn: number
  account: PublicAccount
  identities: PublicIdentity[]
  settings: UserRegionalSettings
}

export type SignInResult =
  | { kind: 'session'; session: PublicSession }
  | { kind: 'link_required'; existingProviders: string[] }

export interface AuthService {
  signInWithIdentity(identity: VerifiedIdentity): Promise<SignInResult>
  signInDev(input: { subject: string; displayName: string }): Promise<PublicSession>
  refresh(refreshToken: string): Promise<PublicSession>
  logout(refreshToken: string): Promise<void>
  link(accountId: string, identity: VerifiedIdentity): Promise<PublicSession>
  unlink(accountId: string, provider: string): Promise<PublicSession>
  me(accountId: string): Promise<PublicSession>
}

function displayName(givenName: string, familyName: string): string {
  return [givenName, familyName].map((part) => part.trim()).filter(Boolean).join(' ')
}

function isPrivateRelay(identity: { email: string | null; isPrivateRelay: boolean }): boolean {
  if (identity.isPrivateRelay) return true
  return (identity.email ?? '').trim().toLowerCase().endsWith('@privaterelay.appleid.com')
}

function canMatchEmail(identity: VerifiedIdentity): boolean {
  if (isPrivateRelay(identity)) return false
  if (!identity.emailVerified) return false
  return Boolean(identity.email?.trim())
}

function normalize(identity: VerifiedIdentity): VerifiedIdentity {
  const email = identity.email?.trim() || null
  return {
    ...identity,
    subject: identity.subject.trim(),
    email,
    givenName: identity.givenName.trim(),
    familyName: identity.familyName.trim(),
    isPrivateRelay: isPrivateRelay({ email, isPrivateRelay: identity.isPrivateRelay }),
  }
}

export function createAuthService(input: {
  repo: AuthRepository
  config: AppConfig
  now?: () => Date
}): AuthService {
  const repo = input.repo
  const config = input.config
  const now = input.now ?? (() => new Date())

  async function publicSession(account: AccountRow, refreshToken: string, sessionId: string): Promise<PublicSession> {
    const identities = await repo.listIdentities(account.id)
    const accessToken = await signAccessToken({
      accountId: account.id,
      sessionId,
      secret: config.jwtSecret,
      ttlSeconds: config.accessTtlSeconds,
      now: now(),
    })
    return {
      accessToken,
      refreshToken,
      expiresIn: config.accessTtlSeconds,
      account: {
        id: account.id,
        displayName: account.displayName,
        givenName: account.givenName,
        familyName: account.familyName,
      },
      identities: identities.map(publicIdentity),
      settings: accountRegional(account),
    }
  }

  async function issue(account: AccountRow, familyId: string): Promise<PublicSession> {
    const sessionId = randomUUID()
    const refreshToken = newRefreshToken()
    await repo.insertSession({
      id: sessionId,
      accountId: account.id,
      familyId,
      refreshTokenHash: hashToken(refreshToken),
      expiresAt: new Date(now().getTime() + config.refreshTtlSeconds * 1000),
      revokedAt: null,
      replacedBy: null,
    })
    return publicSession(account, refreshToken, sessionId)
  }

  async function rememberName(accountId: string, givenName: string, familyName: string): Promise<AccountRow> {
    return repo.updateNamesIfEmpty(accountId, {
      givenName,
      familyName,
      displayName: displayName(givenName, familyName),
    })
  }

  return {
    async signInWithIdentity(raw) {
      const identity = normalize(raw)
      if (!identity.subject) throw new AppError('invalid_identity_token', 401)
      const existing = await repo.findIdentity(identity.provider, identity.subject)
      if (existing) {
        const account = await rememberName(existing.accountId, identity.givenName, identity.familyName)
        return { kind: 'session', session: await issue(account, randomUUID()) }
      }
      if (canMatchEmail(identity)) {
        const matches = await repo.findVerifiedEmailMatches(identity.email!)
        if (matches.length > 0) {
          const existingProviders = [...new Set(matches.map((row) => row.provider))]
          return { kind: 'link_required', existingProviders }
        }
      }
      const account: AccountRow = {
        id: randomUUID(),
        givenName: identity.givenName,
        familyName: identity.familyName,
        displayName: displayName(identity.givenName, identity.familyName),
        createdAt: now(),
        regional: defaultUserSettings(),
      }
      await repo.insertAccountAndIdentity(account, identityRecord(account.id, identity))
      return { kind: 'session', session: await issue(account, randomUUID()) }
    },

    async signInDev(raw) {
      if (config.nodeEnv !== 'development') throw new AppError('not_found', 404)
      const subject = raw.subject.trim()
      const name = raw.displayName.trim()
      if (subject.length < 3 || subject.length > 200) throw new AppError('invalid_request', 400)
      const existing = await repo.findIdentity('dev', subject)
      if (existing) {
        const account = await rememberName(existing.accountId, name, '')
        return issue(account, randomUUID())
      }
      const account: AccountRow = {
        id: randomUUID(),
        givenName: name,
        familyName: '',
        displayName: name,
        createdAt: now(),
        regional: defaultUserSettings(),
      }
      await repo.insertAccountAndIdentity(account, {
        id: randomUUID(),
        accountId: account.id,
        provider: 'dev',
        subject,
        email: null,
        emailVerified: false,
        isPrivateRelay: false,
      })
      return issue(account, randomUUID())
    },

    async refresh(refreshToken) {
      const sessionId = randomUUID()
      const nextRefresh = newRefreshToken()
      const rotated = await repo.rotateSession(hashToken(refreshToken), now(), (current) => ({
        id: sessionId,
        accountId: current.accountId,
        familyId: current.familyId,
        refreshTokenHash: hashToken(nextRefresh),
        expiresAt: new Date(now().getTime() + config.refreshTtlSeconds * 1000),
        revokedAt: null,
        replacedBy: null,
      }))
      if (rotated.status !== 'ok') throw new AppError('session_expired', 401)
      const account = await repo.getAccount(rotated.accountId)
      if (!account) throw new AppError('session_expired', 401)
      return publicSession(account, nextRefresh, sessionId)
    },

    async logout(refreshToken) {
      await repo.revokeFamilyByHash(hashToken(refreshToken), now())
    },

    async link(accountId, raw) {
      const identity = normalize(raw)
      if (!identity.subject) throw new AppError('invalid_identity_token', 401)
      const account = await repo.getAccount(accountId)
      if (!account) throw new AppError('session_expired', 401)
      const existing = await repo.findIdentity(identity.provider, identity.subject)
      if (existing && existing.accountId !== accountId) throw new AppError('identity_in_use', 409)
      if (!existing) {
        if (canMatchEmail(identity)) {
          const matches = await repo.findVerifiedEmailMatches(identity.email!)
          if (matches.some((row) => row.accountId !== accountId)) {
            throw new AppError('email_owned_by_other_account', 409)
          }
        }
        await repo.insertIdentity(identityRecord(accountId, identity))
      }
      const session = await issue(account, randomUUID())
      return session
    },

    async unlink(accountId, provider) {
      if (provider !== 'apple' && provider !== 'google' && provider !== 'dev') {
        throw new AppError('invalid_request', 400)
      }
      const identities = await repo.listIdentities(accountId)
      if (!identities.some((row) => row.provider === provider)) throw new AppError('not_found', 404)
      if (identities.length <= 1) throw new AppError('last_identity', 409)
      await repo.deleteIdentity(accountId, provider)
      const account = await repo.getAccount(accountId)
      if (!account) throw new AppError('not_found', 404)
      return issue(account, randomUUID())
    },

    async me(accountId) {
      const account = await repo.getAccount(accountId)
      if (!account) throw new AppError('not_found', 404)
      const identities = await repo.listIdentities(accountId)
      return {
        accessToken: '',
        refreshToken: '',
        expiresIn: config.accessTtlSeconds,
        account: {
          id: account.id,
          displayName: account.displayName,
          givenName: account.givenName,
          familyName: account.familyName,
        },
        identities: identities.map(publicIdentity),
        settings: accountRegional(account),
      }
    },
  }
}

function identityRecord(accountId: string, identity: VerifiedIdentity): IdentityRow {
  return {
    id: randomUUID(),
    accountId,
    provider: identity.provider,
    subject: identity.subject,
    email: identity.email,
    emailVerified: identity.emailVerified,
    isPrivateRelay: identity.isPrivateRelay,
  }
}

function publicIdentity(row: IdentityRow): PublicIdentity {
  return {
    provider: row.provider,
    email: row.email,
    isPrivateRelay: row.isPrivateRelay,
  }
}

export type { ProviderName }
