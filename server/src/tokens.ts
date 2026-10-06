import { createHash, randomBytes } from 'node:crypto'
import { SignJWT, jwtVerify } from 'jose'

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

export function newRefreshToken(): string {
  return `mr1.${randomBytes(32).toString('base64url')}`
}

export async function signAccessToken(input: {
  accountId: string
  sessionId: string
  secret: string
  ttlSeconds: number
  now?: Date
}): Promise<string> {
  const now = input.now ?? new Date()
  const key = new TextEncoder().encode(input.secret)
  const exp = Math.floor(now.getTime() / 1000) + input.ttlSeconds
  return new SignJWT({ sid: input.sessionId, typ: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(input.accountId)
    .setIssuer('mealroutine')
    .setAudience('mealroutine-ios')
    .setIssuedAt(Math.floor(now.getTime() / 1000))
    .setExpirationTime(exp)
    .sign(key)
}

export async function verifyAccessToken(token: string, secret: string): Promise<{ accountId: string; sessionId: string }> {
  const key = new TextEncoder().encode(secret)
  const { payload } = await jwtVerify(token, key, {
    issuer: 'mealroutine',
    audience: 'mealroutine-ios',
  })
  if (payload.typ !== 'access' || typeof payload.sub !== 'string' || typeof payload.sid !== 'string') {
    throw new Error('invalid access token')
  }
  return { accountId: payload.sub, sessionId: payload.sid }
}
