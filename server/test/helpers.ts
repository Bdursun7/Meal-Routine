import type { AppConfig } from '../src/config.js'
import { AppError } from '../src/errors.js'
import type { IdentityVerifier } from '../src/jwks.js'
import type { VerifiedIdentity } from '../src/authService.js'
import { createMemoryRepository, type MemoryRepository } from '../src/repository.js'

export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    nodeEnv: 'development',
    databaseUrl: '',
    jwtSecret: 'test-secret-must-be-at-least-32-characters',
    googleClientId: 'test-google-client',
    appleBundleId: 'com.mealroutine.app',
    accessTtlSeconds: 900,
    refreshTtlSeconds: 1000,
    port: 8080,
    rateLimitMax: 100,
    rateLimitWindowMs: 60_000,
    apiVersion: 'v1',
    corsOrigin: '',
    sentryDsn: '',
    metricsToken: '',
    ...overrides,
  }
}

export function testVerifier(): IdentityVerifier {
  return {
    async verifyApple(token) {
      return decode(token, 'apple')
    },
    async verifyGoogle(token) {
      return decode(token, 'google')
    },
  }
}

export function identityToken(claims: Partial<VerifiedIdentity> & { subject: string }): string {
  return JSON.stringify(claims)
}

export function memoryRepo(): MemoryRepository {
  return createMemoryRepository()
}

function decode(token: string, provider: 'apple' | 'google'): VerifiedIdentity {
  let body: Partial<VerifiedIdentity>
  try {
    body = JSON.parse(token) as Partial<VerifiedIdentity>
  } catch {
    throw new AppError('invalid_identity_token', 401)
  }
  if (!body.subject) throw new AppError('invalid_identity_token', 401)
  return {
    provider,
    subject: body.subject,
    email: body.email ?? null,
    emailVerified: body.emailVerified ?? false,
    isPrivateRelay: body.isPrivateRelay ?? false,
    givenName: body.givenName ?? '',
    familyName: body.familyName ?? '',
  }
}
