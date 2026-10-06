import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { apnsConfigFromEnv, createFcmSender, createLogSender, notificationCopy } from '../src/notifications.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'

describe('notifications', () => {
  it('groups vetoes inside two minutes and keeps recipe text out of the payload', async () => {
    const start = Date.now()
    let clock = new Date(start)
    const sender = createLogSender()
    const app = buildApp({
      repo: memoryRepo(),
      config: testConfig(),
      verifier: testVerifier(),
      now: () => clock,
      sender,
    })
    const ada = await signIn(app, 'ada-push')
    const berk = await signIn(app, 'berk-push', 'berk-push@example.com')
    const householdId = await joinHousehold(app, ada.token, berk.token)
    await app.inject({
      method: 'POST',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${ada.token}` },
      payload: { token: 'device-token-ada', platform: 'ios' },
    })

    for (const delay of [0, 30_000, 60_000]) {
      clock = new Date(start + delay)
      const response = await app.inject({
        method: 'POST',
        url: `/v1/households/${householdId}/notifications`,
        headers: { authorization: `Bearer ${berk.token}` },
        payload: { kind: 'meal_veto', mealId: 'meal-1', title: 'Beyti' },
      })
      expect(response.statusCode).toBe(200)
    }

    const pending = await app.inject({
      method: 'GET',
      url: '/v1/notifications/outbox',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(pending.json().batches).toHaveLength(1)
    expect(pending.json().batches[0].eventCount).toBe(3)
    expect(pending.json().batches[0].body).toBe('3 yemek için bu hafta olmaz')
    expect(pending.json().batches[0].body).not.toContain('Beyti')
    expect(pending.json().batches[0].route).toBe('mealroutine://week')
    expect(sender.messages).toHaveLength(0)

    clock = new Date(start + 2 * 60 * 1000)
    const dispatched = await app.inject({
      method: 'POST',
      url: '/v1/notifications/dispatch',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(dispatched.json().sent).toBe(1)
    expect(sender.messages).toHaveLength(1)
    expect(sender.messages[0]?.count).toBe(3)
    expect(JSON.stringify(sender.messages[0])).not.toContain('Beyti')
    expect(JSON.stringify(sender.messages[0])).not.toContain('device-token-ada')
    await app.close()
  })

  it('drops events the recipient turned off, including the master switch', async () => {
    const live = buildApp({ repo: memoryRepo(), config: testConfig(), verifier: testVerifier() })
    const adaLive = await signIn(live, 'ada-prefs')
    const berkLive = await signIn(live, 'berk-prefs', 'berk-prefs@example.com')
    const householdId = await joinHousehold(live, adaLive.token, berkLive.token)
    const saved = await live.inject({
      method: 'PUT',
      url: '/v1/notifications/preferences',
      headers: { authorization: `Bearer ${adaLive.token}` },
      payload: {
        masterEnabled: true,
        invitesEnabled: true,
        weeklyPlanEnabled: true,
        mealVetoEnabled: false,
        mealReplacementEnabled: true,
        planFinalizedEnabled: true,
      },
    })
    expect(saved.statusCode).toBe(200)
    await live.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/notifications`,
      headers: { authorization: `Bearer ${berkLive.token}` },
      payload: { kind: 'meal_veto', mealId: 'meal-1' },
    })
    await live.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/notifications`,
      headers: { authorization: `Bearer ${berkLive.token}` },
      payload: { kind: 'weekly_plan' },
    })
    const mixed = await live.inject({
      method: 'GET',
      url: '/v1/notifications/outbox',
      headers: { authorization: `Bearer ${adaLive.token}` },
    })
    expect(mixed.json().batches.map((batch: { kind: string }) => batch.kind)).toEqual(['weekly_plan'])

    await live.inject({
      method: 'PUT',
      url: '/v1/notifications/preferences',
      headers: { authorization: `Bearer ${adaLive.token}` },
      payload: {
        masterEnabled: false,
        invitesEnabled: true,
        weeklyPlanEnabled: true,
        mealVetoEnabled: true,
        mealReplacementEnabled: true,
        planFinalizedEnabled: true,
      },
    })
    await live.inject({
      method: 'POST',
      url: `/v1/households/${householdId}/notifications`,
      headers: { authorization: `Bearer ${berkLive.token}` },
      payload: { kind: 'plan_finalized' },
    })
    const silenced = await live.inject({
      method: 'GET',
      url: '/v1/notifications/outbox',
      headers: { authorization: `Bearer ${adaLive.token}` },
    })
    expect(silenced.json().batches).toHaveLength(1)
    await live.close()
  })

  it('registers and removes only the caller token', async () => {
    const repo = memoryRepo()
    const app = buildApp({ repo, config: testConfig(), verifier: testVerifier() })
    const ada = await signIn(app, 'ada-token')
    const berk = await signIn(app, 'berk-token', 'berk-token@example.com')
    const anon = await app.inject({
      method: 'POST',
      url: '/v1/notifications/tokens',
      payload: { token: 'device-token-ada', platform: 'ios' },
    })
    expect(anon.statusCode).toBe(401)

    await app.inject({
      method: 'POST',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${ada.token}` },
      payload: { token: 'device-token-ada', platform: 'ios' },
    })
    await app.inject({
      method: 'POST',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${ada.token}` },
      payload: { token: 'device-token-ada', platform: 'ios' },
    })
    const removed = await app.inject({
      method: 'DELETE',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${berk.token}` },
      payload: { token: 'device-token-ada' },
    })
    expect(removed.statusCode).toBe(200)
    const adaTokens = await app.inject({
      method: 'GET',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${ada.token}` },
    })
    expect(adaTokens.json().tokens).toHaveLength(1)
    expect(JSON.stringify(adaTokens.json())).not.toContain('device-token-ada')
    const berkTokens = await app.inject({
      method: 'GET',
      url: '/v1/notifications/tokens',
      headers: { authorization: `Bearer ${berk.token}` },
    })
    expect(berkTokens.json().tokens).toEqual([])

    expect(apnsConfigFromEnv({})).toBeNull()
    expect(createFcmSender(undefined).name).toBe('fcm')
    expect(createFcmSender(undefined).configured).toBe(false)
    expect(notificationCopy('meal_replacement', 1, 'meal-1', '').body).not.toContain('meal-1')
    await app.close()
  })
})

async function joinHousehold(app: ReturnType<typeof buildApp>, ownerToken: string, memberToken: string) {
  const created = await app.inject({
    method: 'POST',
    url: '/v1/households',
    headers: { authorization: `Bearer ${ownerToken}` },
    payload: { name: 'Ev' },
  })
  expect(created.statusCode).toBe(200)
  const household = created.json().household.id as string
  const invited = await app.inject({
    method: 'POST',
    url: `/v1/households/${household}/invites`,
    headers: { authorization: `Bearer ${ownerToken}` },
  })
  expect(invited.statusCode).toBe(200)
  const code = invited.json().household.invites[0].code as string
  const joined = await app.inject({
    method: 'POST',
    url: `/v1/invites/${code}/accept`,
    headers: { authorization: `Bearer ${memberToken}` },
  })
  expect(joined.statusCode).toBe(200)
  return household
}

async function signIn(app: ReturnType<typeof buildApp>, subject: string, email?: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken: identityToken({
        subject,
        email: email ?? null,
        emailVerified: Boolean(email),
        givenName: subject,
      }),
      givenName: subject,
    },
  })
  expect(response.statusCode).toBe(200)
  return { token: response.json().accessToken as string, id: response.json().account.id as string }
}
