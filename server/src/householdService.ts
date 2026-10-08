import { randomInt, randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import {
  INVITE_ALPHABET,
  INVITE_LIFETIME_MS,
  isoTimestamp,
  normalizeInviteCode,
  type HouseholdBody,
  type HouseholdStore,
  type HouseholdTx,
  type InviteRecord,
  type PublicHousehold,
} from './householdTypes.js'
import { householdSettingsFrom, type HouseholdRegionalSettings } from './regional.js'
import type { MemberRole } from './repository.js'

const CODE_ATTEMPTS = 6

export interface HouseholdService {
  /** Fields left out of `settings` copy the creator's own account values. */
  create(accountId: string, name: string, settings?: Partial<HouseholdRegionalSettings>): Promise<HouseholdBody>
  updateSettings(accountId: string, householdId: string, patch: Partial<HouseholdRegionalSettings>): Promise<HouseholdBody>
  current(accountId: string): Promise<HouseholdBody>
  rename(accountId: string, householdId: string, name: string): Promise<HouseholdBody>
  createInvite(accountId: string, householdId: string): Promise<HouseholdBody>
  resendInvite(accountId: string, householdId: string, inviteId: string): Promise<HouseholdBody>
  cancelInvite(accountId: string, householdId: string, inviteId: string): Promise<HouseholdBody>
  acceptInvite(accountId: string, code: string): Promise<HouseholdBody>
  rejectInvite(accountId: string, code: string): Promise<{ status: 'rejected' }>
  removeMember(accountId: string, householdId: string, memberAccountId: string): Promise<HouseholdBody>
  leave(accountId: string, householdId: string): Promise<HouseholdBody>
  transfer(accountId: string, householdId: string, memberAccountId: string): Promise<HouseholdBody>
  deleteHousehold(accountId: string, householdId: string): Promise<HouseholdBody>
}

export function createHouseholdService(store: HouseholdStore, now: () => Date = () => new Date()): HouseholdService {
  return {
    async create(accountId, rawName, requested = {}) {
      const name = cleanName(rawName)
      return store.transaction(async (tx) => {
        const account = await requireAccount(tx, accountId)
        if (await tx.activeMembership(accountId)) throw new AppError('already_in_household', 409)
        const householdId = randomUUID()
        const settings = householdSettingsFrom(account.settings, requested)
        await tx.insertHousehold({ id: householdId, name, ownerAccountId: accountId, settings, now: now() })
        await tx.insertMember({
          id: randomUUID(),
          householdId,
          accountId,
          role: 'owner',
          displayName: account.displayName,
          now: now(),
        })
        await tx.insertPreference(householdId)
        return present(tx, householdId, accountId, now())
      })
    },

    async current(accountId) {
      return store.transaction(async (tx) => {
        const membership = await tx.activeMembership(accountId)
        if (!membership) throw new AppError('not_found', 404)
        return present(tx, membership.householdId, accountId, now())
      })
    },

    async rename(accountId, householdId, rawName) {
      const name = cleanName(rawName)
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        await tx.rename(householdId, name, now())
        return present(tx, householdId, accountId, now())
      })
    },

    async updateSettings(accountId, householdId, patch) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        const household = await tx.household(householdId)
        if (!household) throw new AppError('not_found', 404)
        await tx.saveHouseholdSettings(householdId, { ...household.settings, ...patch }, now())
        return present(tx, householdId, accountId, now())
      })
    },

    async createInvite(accountId, householdId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        const members = await tx.members(householdId)
        if (members.length >= 2) throw new AppError('household_full', 409)
        const clock = now()
        await tx.expireInvites(householdId, clock)
        const pending = await tx.pendingInvites(householdId)
        if (pending.length > 0) throw new AppError('duplicate_invite', 409)
        const invite = await insertUniqueInvite(tx, {
          householdId,
          createdBy: accountId,
          expiresAt: new Date(clock.getTime() + INVITE_LIFETIME_MS),
        })
        void invite
        return present(tx, householdId, accountId, clock)
      })
    },

    async resendInvite(accountId, householdId, inviteId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        const invite = await tx.lockInviteById(inviteId)
        if (!invite || invite.householdId !== householdId) throw new AppError('invite_not_found', 404)
        assertResendable(invite)
        const clock = now()
        if (invite.status !== 'pending') {
          await tx.expireInvites(householdId, clock)
          const pending = await tx.pendingInvites(householdId)
          if (pending.some((row) => row.id !== invite.id)) throw new AppError('duplicate_invite', 409)
        }
        invite.status = 'pending'
        invite.expiresAt = new Date(clock.getTime() + INVITE_LIFETIME_MS)
        await tx.saveInvite(invite)
        return present(tx, householdId, accountId, clock)
      })
    },

    async cancelInvite(accountId, householdId, inviteId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        const invite = await tx.lockInviteById(inviteId)
        if (!invite || invite.householdId !== householdId) throw new AppError('invite_not_found', 404)
        if (invite.status === 'accepted' || invite.status === 'rejected') {
          throw new AppError('invite_closed', 409)
        }
        if (invite.status === 'pending' || invite.status === 'expired') {
          invite.status = 'cancelled'
          await tx.saveInvite(invite)
        }
        return present(tx, householdId, accountId, now())
      })
    },

    async acceptInvite(accountId, rawCode) {
      const code = normalizeInviteCode(rawCode)
      if (code.length !== 6) throw new AppError('invite_not_found', 404)
      return store.transaction(async (tx) => {
        const account = await requireAccount(tx, accountId)
        const invite = await tx.lockInviteByCode(code)
        if (!invite) throw new AppError('invite_not_found', 404)
        await tx.lockHousehold(invite.householdId)
        const clock = now()
        await ensurePending(tx, invite, clock)
        const existing = await tx.activeMembership(accountId)
        if (existing?.householdId === invite.householdId) throw new AppError('already_member', 409)
        if (existing) throw new AppError('already_in_household', 409)
        const household = await tx.household(invite.householdId)
        if (!household || household.deletedAt) throw new AppError('invite_not_found', 404)
        const members = await tx.members(invite.householdId)
        if (members.length >= 2) throw new AppError('household_full', 409)
        await tx.insertMember({
          id: randomUUID(),
          householdId: invite.householdId,
          accountId,
          role: 'member',
          displayName: account.displayName,
          now: clock,
        })
        invite.status = 'accepted'
        invite.usedAt = clock
        invite.usedBy = accountId
        await tx.saveInvite(invite)
        return present(tx, invite.householdId, accountId, clock)
      })
    },

    async rejectInvite(accountId, rawCode) {
      const code = normalizeInviteCode(rawCode)
      if (code.length !== 6) throw new AppError('invite_not_found', 404)
      return store.transaction(async (tx) => {
        await requireAccount(tx, accountId)
        const invite = await tx.lockInviteByCode(code)
        if (!invite) throw new AppError('invite_not_found', 404)
        const clock = now()
        await ensurePending(tx, invite, clock)
        invite.status = 'rejected'
        invite.usedAt = clock
        invite.usedBy = accountId
        await tx.saveInvite(invite)
        return { status: 'rejected' as const }
      })
    },

    async removeMember(accountId, householdId, memberAccountId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        if (memberAccountId === accountId) throw new AppError('invalid_request', 400)
        const members = await tx.members(householdId)
        const target = members.find((member) => member.accountId === memberAccountId)
        if (!target) throw new AppError('not_found', 404)
        await tx.markLeft(target.id, now())
        return present(tx, householdId, accountId, now())
      })
    },

    async leave(accountId, householdId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        const membership = await requireMember(tx, householdId, accountId)
        const members = await tx.members(householdId)
        const clock = now()
        if (membership.role === 'owner') {
          const next = members.find((member) => member.accountId !== accountId)
          await tx.markLeft(membership.memberId, clock)
          if (!next) {
            await tx.cancelPending(householdId)
            await tx.softDelete(householdId, clock)
          } else {
            await tx.setRole(next.id, 'owner')
            await tx.setOwner(householdId, next.accountId, clock)
          }
          return { household: null }
        }
        await tx.markLeft(membership.memberId, clock)
        return { household: null }
      })
    },

    async transfer(accountId, householdId, memberAccountId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        const membership = await requireOwner(tx, householdId, accountId)
        if (memberAccountId === accountId) throw new AppError('invalid_request', 400)
        const members = await tx.members(householdId)
        const next = members.find((member) => member.accountId === memberAccountId && member.role === 'member')
        if (!next) throw new AppError('not_found', 404)
        const clock = now()
        await tx.setRole(membership.memberId, 'member')
        await tx.setRole(next.id, 'owner')
        await tx.setOwner(householdId, next.accountId, clock)
        return present(tx, householdId, accountId, clock)
      })
    },

    async deleteHousehold(accountId, householdId) {
      return store.transaction(async (tx) => {
        await tx.lockHousehold(householdId)
        await requireOwner(tx, householdId, accountId)
        const clock = now()
        const members = await tx.members(householdId)
        for (const member of members) await tx.markLeft(member.id, clock)
        await tx.cancelPending(householdId)
        await tx.softDelete(householdId, clock)
        return { household: null }
      })
    },
  }
}

function cleanName(raw: string): string {
  const name = raw.trim()
  if (!name || name.length > 80) throw new AppError('name_empty', 400)
  return name
}

async function requireAccount(tx: HouseholdTx, accountId: string) {
  const account = await tx.account(accountId)
  if (!account) throw new AppError('not_found', 404)
  return account
}

async function requireMember(tx: HouseholdTx, householdId: string, accountId: string) {
  const household = await tx.household(householdId)
  if (!household || household.deletedAt) throw new AppError('not_found', 404)
  const membership = await tx.activeMembership(accountId)
  if (!membership || membership.householdId !== householdId) throw new AppError('forbidden', 403)
  return membership
}

async function requireOwner(tx: HouseholdTx, householdId: string, accountId: string) {
  const membership = await requireMember(tx, householdId, accountId)
  if (membership.role !== 'owner') throw new AppError('forbidden', 403)
  return membership
}

function assertResendable(invite: InviteRecord): void {
  if (invite.status === 'accepted' || invite.status === 'rejected' || invite.status === 'cancelled') {
    throw new AppError('invite_closed', 409)
  }
}

async function ensurePending(tx: HouseholdTx, invite: InviteRecord, now: Date): Promise<void> {
  if (invite.status === 'cancelled') throw new AppError('invite_cancelled', 409)
  if (invite.status === 'expired') throw new AppError('invite_expired', 409)
  if (invite.status !== 'pending') throw new AppError('invite_closed', 409)
  if (invite.expiresAt.getTime() <= now.getTime()) {
    invite.status = 'expired'
    await tx.saveInvite(invite)
    throw new AppError('invite_expired', 409)
  }
}

async function insertUniqueInvite(
  tx: HouseholdTx,
  input: { householdId: string; createdBy: string; expiresAt: Date },
): Promise<InviteRecord> {
  for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt += 1) {
    const invite: InviteRecord = {
      id: randomUUID(),
      householdId: input.householdId,
      createdBy: input.createdBy,
      code: randomCode(),
      status: 'pending',
      expiresAt: input.expiresAt,
      usedAt: null,
      usedBy: null,
    }
    try {
      await tx.insertInvite(invite)
      return invite
    } catch (error) {
      if (error instanceof AppError && error.code === 'invite_code_collision') continue
      throw error
    }
  }
  throw new AppError('invite_code_collision', 409)
}

function randomCode(): string {
  let code = ''
  for (let index = 0; index < 6; index += 1) {
    code += INVITE_ALPHABET[randomInt(INVITE_ALPHABET.length)]
  }
  return code
}

async function present(tx: HouseholdTx, householdId: string, accountId: string, now: Date): Promise<HouseholdBody> {
  const household = await tx.household(householdId)
  if (!household || household.deletedAt) return { household: null }
  const members = await tx.members(householdId)
  const me = members.find((member) => member.accountId === accountId)
  if (!me) return { household: null }
  await tx.expireInvites(householdId, now)
  const invites = me.role === 'owner' ? await tx.pendingInvites(householdId) : []
  const body: PublicHousehold = {
    id: household.id,
    name: household.name,
    role: me.role,
    members: members.map((member) => ({
      accountId: member.accountId,
      displayName: member.displayName,
      role: member.role,
    })),
    invites: invites.map((invite) => ({
      id: invite.id,
      code: invite.code,
      status: invite.status,
      expiresAt: isoTimestamp(invite.expiresAt),
    })),
    settings: { ...household.settings },
  }
  return { household: body }
}

export type { MemberRole }
