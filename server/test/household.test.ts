import { describe, expect, it } from 'vitest'
import { buildApp } from '../src/app.js'
import { identityToken, memoryRepo, testConfig, testVerifier } from './helpers.js'
import type { MemoryRepository } from '../src/repository.js'
import type { FastifyInstance } from 'fastify'

const day = 24 * 60 * 60 * 1000

function session() {
  const repo: MemoryRepository = memoryRepo()
  const clock = { now: new Date('2030-06-01T00:00:00.000Z') }
  const app = buildApp({
    repo,
    config: testConfig(),
    verifier: testVerifier(),
    householdNow: () => clock.now,
  })
  return { repo, app, clock }
}

async function signIn(app: FastifyInstance, subject: string, givenName: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/apple',
    payload: {
      identityToken: identityToken({ subject, givenName, familyName: '' }),
      givenName,
    },
  })
  expect(response.statusCode).toBe(200)
  const body = response.json()
  return {
    token: body.accessToken as string,
    accountId: body.account.id as string,
    auth: { authorization: `Bearer ${body.accessToken}` },
  }
}

async function createHousehold(app: FastifyInstance, auth: { authorization: string }, name = 'Ev') {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/households',
    headers: auth,
    payload: { name },
  })
  expect(response.statusCode).toBe(200)
  return response.json().household as {
    id: string
    name: string
    role: string
    members: { accountId: string; role: string; displayName: string }[]
    invites: { id: string; code: string; status: string; expiresAt: string }[]
  }
}

describe('household lifecycle', () => {
  it('creates, renames, and refuses a second household', async () => {
    const { app } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const household = await createHousehold(app, ada.auth, '  Akşam  ')
    expect(household.name).toBe('Akşam')
    expect(household.role).toBe('owner')
    expect(household.members).toHaveLength(1)

    const renamed = await app.inject({
      method: 'PATCH',
      url: `/v1/households/${household.id}`,
      headers: ada.auth,
      payload: { name: 'Yeni ev' },
    })
    expect(renamed.statusCode).toBe(200)
    expect(renamed.json().household.name).toBe('Yeni ev')

    const again = await app.inject({
      method: 'POST',
      url: '/v1/households',
      headers: ada.auth,
      payload: { name: 'İkinci' },
    })
    expect(again.statusCode).toBe(409)
    expect(again.json().error).toBe('already_in_household')

    const blank = await app.inject({
      method: 'PATCH',
      url: `/v1/households/${household.id}`,
      headers: ada.auth,
      payload: { name: '   ' },
    })
    expect(blank.statusCode).toBe(400)
    expect(blank.json().error).toBe('name_empty')
    await app.close()
  })

  it('invites once, resends, cancels, rejects, and blocks a used or expired code', async () => {
    const { app, clock } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const bea = await signIn(app, 'bea', 'Bea')
    const household = await createHousehold(app, ada.auth)

    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    expect(invited.statusCode).toBe(200)
    const invite = invited.json().household.invites[0]
    expect(invite.code).toHaveLength(6)
    expect(invite.status).toBe('pending')

    const duplicate = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    expect(duplicate.statusCode).toBe(409)
    expect(duplicate.json().error).toBe('duplicate_invite')

    clock.now = new Date(clock.now.getTime() + day)
    const resent = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites/${invite.id}/resend`,
      headers: ada.auth,
    })
    expect(resent.statusCode).toBe(200)
    const resentInvite = resent.json().household.invites[0]
    expect(resentInvite.code).toBe(invite.code)
    expect(resentInvite.expiresAt > invite.expiresAt).toBe(true)
    expect(resent.json().household.invites).toHaveLength(1)

    const rejected = await app.inject({
      method: 'POST',
      url: `/v1/invites/${invite.code}/reject`,
      headers: bea.auth,
    })
    expect(rejected.statusCode).toBe(200)
    expect(rejected.json()).toEqual({ status: 'rejected' })
    const used = await app.inject({
      method: 'POST',
      url: `/v1/invites/${invite.code}/accept`,
      headers: bea.auth,
    })
    expect(used.statusCode).toBe(409)
    expect(used.json().error).toBe('invite_closed')

    const next = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    expect(next.statusCode).toBe(200)
    const second = next.json().household.invites[0]
    const cancelled = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites/${second.id}/cancel`,
      headers: ada.auth,
    })
    expect(cancelled.statusCode).toBe(200)
    expect(cancelled.json().household.invites).toHaveLength(0)
    const afterCancel = await app.inject({
      method: 'POST',
      url: `/v1/invites/${second.code}/accept`,
      headers: bea.auth,
    })
    expect(afterCancel.statusCode).toBe(409)
    expect(afterCancel.json().error).toBe('invite_cancelled')

    const third = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const expiring = third.json().household.invites[0]
    clock.now = new Date(clock.now.getTime() + 8 * day)
    const expired = await app.inject({
      method: 'POST',
      url: `/v1/invites/${expiring.code}/accept`,
      headers: bea.auth,
    })
    expect(expired.statusCode).toBe(409)
    expect(expired.json().error).toBe('invite_expired')
    const missing = await app.inject({
      method: 'POST',
      url: '/v1/invites/ZZZZZZ/accept',
      headers: bea.auth,
    })
    expect(missing.statusCode).toBe(404)
    expect(missing.json().error).toBe('invite_not_found')
    await app.close()
  })

  it('accepts one partner, blocks a third, and keeps personal accounts when people leave', async () => {
    const { app, repo } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const bea = await signIn(app, 'bea', 'Bea')
    const cem = await signIn(app, 'cem', 'Cem')
    const household = await createHousehold(app, ada.auth)
    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const code = invited.json().household.invites[0].code as string

    const joined = await app.inject({
      method: 'POST',
      url: `/v1/invites/${code}/accept`,
      headers: bea.auth,
    })
    expect(joined.statusCode).toBe(200)
    expect(joined.json().household.role).toBe('member')
    expect(joined.json().household.members).toHaveLength(2)
    expect(joined.json().household.invites).toEqual([])

    const fullInvite = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    expect(fullInvite.statusCode).toBe(409)
    expect(fullInvite.json().error).toBe('household_full')

    const ownHouse = await createHousehold(app, cem.auth, 'Cem evi')
    const adaAgain = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    expect(adaAgain.statusCode).toBe(409)

    const removed = await app.inject({
      method: 'DELETE',
      url: `/v1/households/${household.id}/members/${bea.accountId}`,
      headers: ada.auth,
    })
    expect(removed.statusCode).toBe(200)
    expect(removed.json().household.members).toHaveLength(1)
    const beaStill = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: bea.auth })
    expect(beaStill.statusCode).toBe(200)
    expect(beaStill.json().account.id).toBe(bea.accountId)
    const beaHome = await app.inject({ method: 'GET', url: '/v1/households/current', headers: bea.auth })
    expect(beaHome.statusCode).toBe(404)

    const reinvite = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const reCode = reinvite.json().household.invites[0].code as string
    const cemJoins = await app.inject({
      method: 'POST',
      url: `/v1/invites/${reCode}/accept`,
      headers: cem.auth,
    })
    expect(cemJoins.statusCode).toBe(409)
    expect(cemJoins.json().error).toBe('already_in_household')

    const beaJoins = await app.inject({
      method: 'POST',
      url: `/v1/invites/${reCode}/accept`,
      headers: bea.auth,
    })
    expect(beaJoins.statusCode).toBe(200)

    const transferred = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/transfer`,
      headers: ada.auth,
      payload: { accountId: bea.accountId },
    })
    expect(transferred.statusCode).toBe(200)
    expect(transferred.json().household.role).toBe('member')
    expect(transferred.json().household.members.find((member: { accountId: string }) => member.accountId === bea.accountId).role).toBe('owner')

    const adaDeletes = await app.inject({
      method: 'DELETE',
      url: `/v1/households/${household.id}`,
      headers: ada.auth,
    })
    expect(adaDeletes.statusCode).toBe(403)

    const ownerLeaves = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/leave`,
      headers: bea.auth,
    })
    expect(ownerLeaves.statusCode).toBe(200)
    expect(ownerLeaves.json()).toEqual({ household: null })
    const adaNow = await app.inject({ method: 'GET', url: '/v1/households/current', headers: ada.auth })
    expect(adaNow.statusCode).toBe(200)
    expect(adaNow.json().household.role).toBe('owner')
    expect(await repo.preferenceRetained(household.id)).toBe(true)

    const memberLeaves = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/leave`,
      headers: ada.auth,
    })
    expect(memberLeaves.statusCode).toBe(200)
    expect(await repo.preferenceRetained(household.id)).toBe(true)
    const adaMe = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: ada.auth })
    expect(adaMe.statusCode).toBe(200)
    expect(ownHouse.id).not.toBe(household.id)
    const cemMe = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: cem.auth })
    expect(cemMe.statusCode).toBe(200)
    await app.close()
  })

  it('lets a lone owner leave by closing the household without deleting the account', async () => {
    const { app, repo } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const household = await createHousehold(app, ada.auth)
    const left = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/leave`,
      headers: ada.auth,
    })
    expect(left.statusCode).toBe(200)
    expect(left.json()).toEqual({ household: null })
    const current = await app.inject({ method: 'GET', url: '/v1/households/current', headers: ada.auth })
    expect(current.statusCode).toBe(404)
    const me = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: ada.auth })
    expect(me.statusCode).toBe(200)
    expect(await repo.preferenceRetained(household.id)).toBe(true)
    const gone = await app.inject({
      method: 'GET',
      url: `/v1/households/${household.id}`,
      headers: ada.auth,
    })
    expect(gone.statusCode).toBe(404)
    await app.close()
  })

  it('returns 403 to another household and 403 when a member acts as owner', async () => {
    const { app } = session()
    const ada = await signIn(app, 'ada', 'Ada')
    const bea = await signIn(app, 'bea', 'Bea')
    const cem = await signIn(app, 'cem', 'Cem')
    const household = await createHousehold(app, ada.auth)
    const invited = await app.inject({
      method: 'POST',
      url: `/v1/households/${household.id}/invites`,
      headers: ada.auth,
    })
    const invite = invited.json().household.invites[0]
    await app.inject({ method: 'POST', url: `/v1/invites/${invite.code}/accept`, headers: bea.auth })
    const other = await createHousehold(app, cem.auth, 'Başka')

    const strangerRoutes: { method: 'PATCH' | 'POST' | 'DELETE'; url: string; payload?: { name: string } | { accountId: string } }[] = [
      { method: 'PATCH', url: `/v1/households/${household.id}`, payload: { name: 'Hayır' } },
      { method: 'POST', url: `/v1/households/${household.id}/invites` },
      { method: 'POST', url: `/v1/households/${household.id}/invites/${invite.id}/resend` },
      { method: 'POST', url: `/v1/households/${household.id}/invites/${invite.id}/cancel` },
      { method: 'DELETE', url: `/v1/households/${household.id}/members/${bea.accountId}` },
      { method: 'POST', url: `/v1/households/${household.id}/leave` },
      { method: 'POST', url: `/v1/households/${household.id}/transfer`, payload: { accountId: bea.accountId } },
      { method: 'DELETE', url: `/v1/households/${household.id}` },
    ]
    for (const route of strangerRoutes) {
      const response = await app.inject({
        method: route.method,
        url: route.url,
        headers: cem.auth,
        payload: route.payload,
      })
      expect(response.statusCode, `${route.method} ${route.url}`).toBe(403)
      expect(response.json().error).toBe('forbidden')
    }

    const memberRoutes: { method: 'PATCH' | 'POST' | 'DELETE'; url: string; payload?: { name: string } | { accountId: string } }[] = [
      { method: 'PATCH', url: `/v1/households/${household.id}`, payload: { name: 'Hayır' } },
      { method: 'POST', url: `/v1/households/${household.id}/invites` },
      { method: 'POST', url: `/v1/households/${household.id}/invites/${invite.id}/cancel` },
      { method: 'DELETE', url: `/v1/households/${household.id}/members/${ada.accountId}` },
      { method: 'POST', url: `/v1/households/${household.id}/transfer`, payload: { accountId: ada.accountId } },
      { method: 'DELETE', url: `/v1/households/${household.id}` },
    ]
    for (const route of memberRoutes) {
      const response = await app.inject({
        method: route.method,
        url: route.url,
        headers: bea.auth,
        payload: route.payload,
      })
      expect(response.statusCode, `${route.method} ${route.url}`).toBe(403)
      expect(response.json().error).toBe('forbidden')
    }

    const missing = await app.inject({
      method: 'PATCH',
      url: '/v1/households/99999999-9999-4999-8999-999999999999',
      headers: ada.auth,
      payload: { name: 'Yok' },
    })
    expect(missing.statusCode).toBe(404)
    expect(other.name).toBe('Başka')
    await app.close()
  })
})
