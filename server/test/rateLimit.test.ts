import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { createRateLimiter } from '../src/rateLimit.js'
import { memoryRepo, testConfig, testVerifier } from './helpers.js'

describe('rate limit', () => {
  it('stops auth calls after the configured maximum', async () => {
    const limiter = createRateLimiter({ windowMs: 60_000, max: 2 })
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig({ rateLimitMax: 2 }),
      verifier: testVerifier(),
      rateLimiter: limiter,
    })
    const payload = { refreshToken: 'mr1.not-a-real-token-but-long-enough' }
    const first = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload })
    const second = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload })
    const third = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload })
    expect(first.statusCode).not.toBe(429)
    expect(second.statusCode).not.toBe(429)
    expect(third.statusCode).toBe(429)
    expect(third.json()).toEqual({ error: 'rate_limited' })
    const health = await app.inject({ method: 'GET', url: '/health' })
    expect(health.statusCode).toBe(200)
    await app.close()
  })
})
