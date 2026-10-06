import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

const householdId = '11111111-1111-4111-8111-111111111111'

describe('household authorization', () => {
  it('returns 404 when the caller is not a member', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const owner = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: {
        identityToken: identityToken({ subject: 'owner', givenName: 'Ada', familyName: '' }),
        givenName: 'Ada',
      },
    })
    const stranger = await app.inject({
      method: 'POST',
      url: '/v1/auth/google',
      payload: {
        identityToken: identityToken({
          subject: 'stranger',
          email: 'other@example.com',
          emailVerified: true,
        }),
      },
    })
    expect(owner.statusCode).toBe(200)
    expect(stranger.statusCode).toBe(200)
    const ownerId = owner.json().account.id as string
    repo.seedMember(householdId, ownerId, 'owner')

    const denied = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}`,
      headers: { authorization: `Bearer ${stranger.json().accessToken}` },
    })
    expect([403, 404]).toContain(denied.statusCode)
    expect(denied.body).not.toContain('Ada')

    const deniedWrite = await app.inject({
      method: 'PUT',
      url: `/v1/households/${householdId}/board`,
      headers: { authorization: `Bearer ${stranger.json().accessToken}` },
      payload: { note: 'nope' },
    })
    expect([403, 404]).toContain(deniedWrite.statusCode)

    const allowed = await app.inject({
      method: 'GET',
      url: `/v1/households/${householdId}`,
      headers: { authorization: `Bearer ${owner.json().accessToken}` },
    })
    expect(allowed.statusCode).toBe(200)
    expect(allowed.json()).toEqual({ id: householdId, role: 'owner' })
    await app.close()
  })
})
