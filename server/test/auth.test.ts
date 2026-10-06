import { describe, expect, it } from 'vitest'
import { createAuthService } from '../src/authService.js'
import { buildApp } from '../src/app.js'
import { createJwksVerifier } from '../src/jwks.js'
import { signAccessToken } from '../src/tokens.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

describe('auth service', () => {
  it('stores the Apple name from the first login and keeps it', async () => {
    const repo = memoryRepo()
    const service = createAuthService({ repo, config: testConfig() })
    const first = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-user-1',
      email: 'ada@privaterelay.appleid.com',
      emailVerified: true,
      isPrivateRelay: true,
      givenName: 'Ada',
      familyName: 'Lovelace',
    })
    expect(first.kind).toBe('session')
    if (first.kind !== 'session') return
    expect(first.session.account.givenName).toBe('Ada')
    expect(first.session.account.familyName).toBe('Lovelace')
    expect(first.session.identities[0]?.isPrivateRelay).toBe(true)

    const second = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-user-1',
      email: null,
      emailVerified: false,
      isPrivateRelay: false,
      givenName: '',
      familyName: '',
    })
    expect(second.kind).toBe('session')
    if (second.kind !== 'session') return
    expect(second.session.account.givenName).toBe('Ada')
    expect(second.session.account.displayName).toBe('Ada Lovelace')
    expect(await repo.countAccounts()).toBe(1)
  })

  it('does not create a second account when Google email matches Apple', async () => {
    const repo = memoryRepo()
    const service = createAuthService({ repo, config: testConfig() })
    const apple = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-user-2',
      email: 'ada@example.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: '',
    })
    expect(apple.kind).toBe('session')
    if (apple.kind !== 'session') return

    const google = await service.signInWithIdentity({
      provider: 'google',
      subject: 'google-user-2',
      email: 'Ada@Example.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: 'Lovelace',
    })
    expect(google).toEqual({ kind: 'link_required', existingProviders: ['apple'] })
    expect(await repo.countAccounts()).toBe(1)
    expect(await repo.findIdentity('google', 'google-user-2')).toBeNull()

    const linked = await service.link(apple.session.account.id, {
      provider: 'google',
      subject: 'google-user-2',
      email: 'ada@example.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: 'Lovelace',
    })
    expect(linked.account.id).toBe(apple.session.account.id)
    expect(linked.identities.map((row) => row.provider).sort()).toEqual(['apple', 'google'])

    const again = await service.signInWithIdentity({
      provider: 'google',
      subject: 'google-user-2',
      email: 'ada@example.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: '',
      familyName: '',
    })
    expect(again.kind).toBe('session')
    if (again.kind !== 'session') return
    expect(again.session.account.id).toBe(apple.session.account.id)
  })

  it('does not treat a private relay address as the same person', async () => {
    const repo = memoryRepo()
    const service = createAuthService({ repo, config: testConfig() })
    await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-relay',
      email: 'hide@privaterelay.appleid.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: '',
    })
    const google = await service.signInWithIdentity({
      provider: 'google',
      subject: 'google-relay',
      email: 'hide@privaterelay.appleid.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Someone',
      familyName: '',
    })
    expect(google.kind).toBe('session')
    expect(await repo.countAccounts()).toBe(2)
  })

  it('rotates refresh tokens and rejects a reused token', async () => {
    const repo = memoryRepo()
    const service = createAuthService({ repo, config: testConfig() })
    const signedIn = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-refresh',
      email: null,
      emailVerified: false,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: '',
    })
    if (signedIn.kind !== 'session') throw new Error('expected session')
    const next = await service.refresh(signedIn.session.refreshToken)
    expect(next.refreshToken).not.toBe(signedIn.session.refreshToken)
    await expect(service.refresh(signedIn.session.refreshToken)).rejects.toMatchObject({ code: 'session_expired' })
    await expect(service.refresh(next.refreshToken)).rejects.toMatchObject({ code: 'session_expired' })
  })

  it('rejects an expired refresh token', async () => {
    let now = new Date('2026-01-01T00:00:00Z')
    const service = createAuthService({
      repo: memoryRepo(),
      config: testConfig({ refreshTtlSeconds: 10 }),
      now: () => now,
    })
    const signedIn = await service.signInWithIdentity({
      provider: 'google',
      subject: 'google-expire',
      email: 'a@example.com',
      emailVerified: true,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: '',
    })
    if (signedIn.kind !== 'session') throw new Error('expected session')
    now = new Date('2026-01-01T00:00:11Z')
    await expect(service.refresh(signedIn.session.refreshToken)).rejects.toMatchObject({ code: 'session_expired' })
  })

  it('logout revokes the refresh family', async () => {
    const service = createAuthService({ repo: memoryRepo(), config: testConfig() })
    const signedIn = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-logout',
      email: null,
      emailVerified: false,
      isPrivateRelay: false,
      givenName: '',
      familyName: '',
    })
    if (signedIn.kind !== 'session') throw new Error('expected session')
    await service.logout(signedIn.session.refreshToken)
    await expect(service.refresh(signedIn.session.refreshToken)).rejects.toMatchObject({ code: 'session_expired' })
  })

  it('refuses to unlink the last identity', async () => {
    const service = createAuthService({ repo: memoryRepo(), config: testConfig() })
    const signedIn = await service.signInWithIdentity({
      provider: 'apple',
      subject: 'apple-only',
      email: null,
      emailVerified: false,
      isPrivateRelay: false,
      givenName: 'Ada',
      familyName: '',
    })
    if (signedIn.kind !== 'session') throw new Error('expected session')
    await expect(service.unlink(signedIn.session.account.id, 'apple')).rejects.toMatchObject({
      code: 'last_identity',
    })
  })
})

describe('auth http', () => {
  it('returns link_required without the email and without a second account', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const apple = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: {
        identityToken: identityToken({
          subject: 'apple-http',
          email: 'ada@example.com',
          emailVerified: true,
          givenName: 'Ada',
          familyName: 'Lovelace',
        }),
        givenName: 'Ada',
        familyName: 'Lovelace',
      },
    })
    expect(apple.statusCode).toBe(200)
    const google = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: {
        identityToken: identityToken({
          subject: 'google-http',
          email: 'ada@example.com',
          emailVerified: true,
        }),
      },
    })
    expect(google.statusCode).toBe(409)
    expect(google.json()).toEqual({ error: 'link_required', existingProviders: ['apple'] })
    expect(google.body).not.toContain('ada@example.com')
    expect(await repo.countAccounts()).toBe(1)
    await app.close()
  })

  it('hides dev login outside development and signs in the same subject twice', async () => {
    const closed = buildApp({
      repo: memoryRepo(),
      config: testConfig({ nodeEnv: 'production' }),
      verifier: testVerifier(),
    })
    const hidden = await closed.inject({
      method: 'POST',
      url: '/v1/auth/dev',
      payload: { subject: 'dev-user-1', displayName: 'Yerel test' },
    })
    expect(hidden.statusCode).toBe(404)
    await closed.close()

    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const first = await app.inject({
      method: 'POST',
      url: '/v1/auth/dev',
      payload: { subject: 'dev-user-1', displayName: 'Yerel test' },
    })
    const second = await app.inject({
      method: 'POST',
      url: '/v1/auth/dev',
      payload: { subject: 'dev-user-1', displayName: 'Başka ad' },
    })
    expect(first.statusCode).toBe(200)
    expect(second.statusCode).toBe(200)
    expect(second.json().account.id).toBe(first.json().account.id)
    expect(second.json().account.displayName).toBe('Yerel test')
    await app.close()
  })

  it('rejects an expired access token', async () => {
    const config = testConfig()
    const app = buildApp({ repo: memoryRepo(), config, verifier: testVerifier() })
    const token = await signAccessToken({
      accountId: '00000000-0000-4000-8000-000000000001',
      sessionId: '00000000-0000-4000-8000-000000000002',
      secret: config.jwtSecret,
      ttlSeconds: -30,
      now: new Date(),
    })
    const me = await app.inject({
      method: 'GET',
      url: '/v1/auth/me',
      headers: { authorization: `Bearer ${token}` },
    })
    expect(me.statusCode).toBe(401)
    expect(me.json()).toEqual({ error: 'session_expired' })
    await app.close()
  })

  it('rejects an unsupported client API version', async () => {
    const app = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      headers: { 'x-client-api-version': '9' },
      payload: { identityToken: identityToken({ subject: 'apple-version' }) },
    })
    expect(response.statusCode).toBe(406)
    expect(response.json()).toEqual({ error: 'unsupported_api_version' })
    await app.close()
  })

  it('refuses Google sign-in when the iOS client id is empty', async () => {
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig({ googleClientId: '' }),
      verifier: createJwksVerifier(testConfig({ googleClientId: '' })),
    })
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: { identityToken: 'a.b.c' },
    })
    expect(response.statusCode).toBe(503)
    expect(response.json()).toEqual({ error: 'google_not_configured' })
    await app.close()
  })
})
