import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose'
import type { AppConfig } from './config.js'
import { AppError } from './errors.js'
import type { VerifiedIdentity } from './authService.js'

export interface IdentityVerifier {
  verifyApple(token: string): Promise<VerifiedIdentity>
  verifyGoogle(token: string): Promise<VerifiedIdentity>
}

const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'))
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'))

function textClaim(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

function boolClaim(value: unknown): boolean {
  return value === true || value === 'true'
}

function mapApple(payload: JWTPayload): VerifiedIdentity {
  const email = textClaim(payload.email) || null
  const relay =
    boolClaim(payload.is_private_email) ||
    (email?.toLowerCase().endsWith('@privaterelay.appleid.com') ?? false)
  return {
    provider: 'apple',
    subject: textClaim(payload.sub),
    email,
    emailVerified: boolClaim(payload.email_verified),
    isPrivateRelay: relay,
    givenName: '',
    familyName: '',
  }
}

function mapGoogle(payload: JWTPayload): VerifiedIdentity {
  const email = textClaim(payload.email) || null
  return {
    provider: 'google',
    subject: textClaim(payload.sub),
    email,
    emailVerified: boolClaim(payload.email_verified),
    isPrivateRelay: false,
    givenName: textClaim(payload.given_name),
    familyName: textClaim(payload.family_name),
  }
}

export function createJwksVerifier(config: AppConfig): IdentityVerifier {
  return {
    async verifyApple(token) {
      try {
        const { payload } = await jwtVerify(token, appleKeys, {
          issuer: 'https://appleid.apple.com',
          audience: config.appleBundleId,
        })
        const identity = mapApple(payload)
        if (!identity.subject) throw new AppError('invalid_identity_token', 401)
        return identity
      } catch (error) {
        if (error instanceof AppError) throw error
        throw new AppError('invalid_identity_token', 401)
      }
    },
    async verifyGoogle(token) {
      if (!config.googleClientId) throw new AppError('google_not_configured', 503)
      try {
        const { payload } = await jwtVerify(token, googleKeys, {
          issuer: ['https://accounts.google.com', 'accounts.google.com'],
          audience: config.googleClientId,
        })
        const identity = mapGoogle(payload)
        if (!identity.subject) throw new AppError('invalid_identity_token', 401)
        return identity
      } catch (error) {
        if (error instanceof AppError) throw error
        throw new AppError('invalid_identity_token', 401)
      }
    },
  }
}
