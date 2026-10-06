import { AppError } from './errors.js'
import type {
  HouseholdRecord,
  HouseholdStore,
  HouseholdTx,
  InviteRecord,
  MemberRecord,
} from './householdTypes.js'
import type { AccountRow, MemberRole } from './repository.js'

interface StoredMember extends MemberRecord {
  leftAt: Date | null
  joinedAt: Date
}

export function createHouseholdMemory(
  accounts: Map<string, AccountRow>,
  syncMembership: (householdId: string, accountId: string, role: MemberRole | null) => void,
): HouseholdStore {
  const households = new Map<string, HouseholdRecord>()
  const members: StoredMember[] = []
  const invites: InviteRecord[] = []
  const preferences = new Set<string>()

  const tx: HouseholdTx = {
    async account(id) {
      const account = accounts.get(id)
      if (!account) return null
      return { id: account.id, displayName: account.displayName }
    },
    async activeMembership(accountId) {
      const member = members.find((row) => row.accountId === accountId && row.leftAt === null)
      if (!member) return null
      const household = households.get(member.householdId)
      if (!household || household.deletedAt) return null
      return { householdId: member.householdId, memberId: member.id, role: member.role }
    },
    async household(id) {
      const household = households.get(id)
      return household ? { ...household } : null
    },
    async lockHousehold() {},
    async members(householdId) {
      return members
        .filter((row) => row.householdId === householdId && row.leftAt === null)
        .sort((left, right) => left.joinedAt.getTime() - right.joinedAt.getTime())
        .map((row) => ({ ...row }))
    },
    async pendingInvites(householdId) {
      return invites
        .filter((row) => row.householdId === householdId && row.status === 'pending')
        .map((row) => ({ ...row }))
    },
    async expireInvites(householdId, now) {
      for (const invite of invites) {
        if (invite.householdId === householdId && invite.status === 'pending' && invite.expiresAt.getTime() <= now.getTime()) {
          invite.status = 'expired'
        }
      }
    },
    async insertHousehold(row) {
      households.set(row.id, {
        id: row.id,
        name: row.name,
        ownerAccountId: row.ownerAccountId,
        deletedAt: null,
      })
    },
    async insertMember(row) {
      if (members.some((member) => member.accountId === row.accountId && member.leftAt === null)) {
        throw new AppError('already_in_household', 409)
      }
      const active = members.filter((member) => member.householdId === row.householdId && member.leftAt === null)
      if (active.length >= 2) throw new AppError('household_full', 409)
      members.push({ ...row, leftAt: null, joinedAt: row.now })
      syncMembership(row.householdId, row.accountId, row.role)
    },
    async insertPreference(householdId) {
      preferences.add(householdId)
    },
    async rename(id, name) {
      const household = households.get(id)
      if (!household || household.deletedAt) throw new AppError('not_found', 404)
      household.name = name
    },
    async setOwner(householdId, accountId) {
      const household = households.get(householdId)
      if (!household) throw new AppError('not_found', 404)
      household.ownerAccountId = accountId
    },
    async setRole(memberId, role) {
      const member = members.find((row) => row.id === memberId && row.leftAt === null)
      if (!member) throw new AppError('not_found', 404)
      member.role = role
      syncMembership(member.householdId, member.accountId, role)
    },
    async markLeft(memberId, now) {
      const member = members.find((row) => row.id === memberId && row.leftAt === null)
      if (!member) return
      member.leftAt = now
      if (member.role === 'owner') member.role = 'member'
      syncMembership(member.householdId, member.accountId, null)
    },
    async softDelete(householdId, now) {
      const household = households.get(householdId)
      if (!household) throw new AppError('not_found', 404)
      household.deletedAt = now
      for (const member of members) {
        if (member.householdId === householdId && member.leftAt === null) {
          member.leftAt = now
          syncMembership(householdId, member.accountId, null)
        }
      }
    },
    async cancelPending(householdId) {
      for (const invite of invites) {
        if (invite.householdId === householdId && invite.status === 'pending') invite.status = 'cancelled'
      }
    },
    async insertInvite(row) {
      if (invites.some((invite) => invite.code === row.code)) throw new AppError('invite_code_collision', 409)
      if (invites.some((invite) => invite.householdId === row.householdId && invite.status === 'pending' && row.status === 'pending')) {
        throw new AppError('duplicate_invite', 409)
      }
      invites.push({ ...row })
    },
    async lockInviteById(id) {
      const invite = invites.find((row) => row.id === id)
      return invite ? { ...invite } : null
    },
    async lockInviteByCode(code) {
      const invite = invites.find((row) => row.code === code)
      return invite ? { ...invite } : null
    },
    async saveInvite(row) {
      const index = invites.findIndex((invite) => invite.id === row.id)
      if (index < 0) throw new AppError('invite_not_found', 404)
      invites[index] = { ...row }
    },
  }

  return {
    async transaction(work) {
      return work(tx)
    },
    async preferenceRetained(householdId) {
      return preferences.has(householdId)
    },
  }
}
