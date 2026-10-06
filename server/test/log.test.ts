import { Writable } from 'node:stream'
import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { redactSensitive } from '../src/log.js'
import { memoryRepo, testConfig, testVerifier } from './helpers.js'

describe('logging', () => {
  it('redacts names, email, and tokens', () => {
    const redacted = JSON.stringify(
      redactSensitive({
        identityToken: 'super-secret-token',
        email: 'ada@example.com',
        givenName: 'Ada',
        nested: { refreshToken: 'mr1.secret', ok: true },
      }),
    )
    expect(redacted).not.toContain('super-secret-token')
    expect(redacted).not.toContain('ada@example.com')
    expect(redacted).not.toContain('Ada')
    expect(redacted).not.toContain('mr1.secret')
    expect(redacted).toContain('[redacted]')
  })

  it('does not write the identity token or name to the server log', async () => {
    const lines: string[] = []
    const stream = new Writable({
      write(chunk, _encoding, callback) {
        lines.push(String(chunk))
        callback()
      },
    })
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: testVerifier(),
      logStream: stream,
    })
    const token = 'super-secret-token-value-xxxx'
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/apple',
      payload: { identityToken: token, givenName: 'Ada Lovelace', familyName: 'Secret' },
    })
    expect(response.statusCode).toBe(401)
    const blob = lines.join('\n')
    expect(blob).not.toContain(token)
    expect(blob).not.toContain('Ada Lovelace')
    expect(blob).not.toContain('Secret')
    await app.close()
  })
})
