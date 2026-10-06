import type { BoardStore } from './boardTypes.js'
import { AppError } from './errors.js'
import type { HouseholdStore } from './householdTypes.js'
import { createMemoryBoard } from './memoryBoard.js'
import { createHouseholdMemory } from './memoryHousehold.js'

export type ProviderName = 'apple' | 'google' | 'dev'
export type MemberRole = 'owner' | 'member'

export interface AccountRow {
  id: string
  displayName: string
  givenName: string
  familyName: string
  createdAt: Date
}

export interface IdentityRow {
  id: string
  accountId: string
  provider: ProviderName
  subject: string
  email: string | null
  emailVerified: boolean
  isPrivateRelay: boolean
}

export interface SessionRow {
  id: string
  accountId: string
  familyId: string
  refreshTokenHash: string
  expiresAt: Date
  revokedAt: Date | null
  replacedBy: string | null
}

export type RotateResult =
  | { status: 'ok'; accountId: string }
  | { status: 'missing' | 'revoked' | 'expired' }

export interface SessionDraft {
  accountId: string
  familyId: string
}

export interface AuthRepository {
  countAccounts(): Promise<number>
  findIdentity(provider: string, subject: string): Promise<IdentityRow | null>
  findVerifiedEmailMatches(email: string): Promise<IdentityRow[]>
  listIdentities(accountId: string): Promise<IdentityRow[]>
  getAccount(id: string): Promise<AccountRow | null>
  insertAccountAndIdentity(account: AccountRow, identity: IdentityRow): Promise<void>
  updateNamesIfEmpty(
    accountId: string,
    names: { givenName: string; familyName: string; displayName: string },
  ): Promise<AccountRow>
  insertIdentity(identity: IdentityRow): Promise<void>
  deleteIdentity(accountId: string, provider: string): Promise<boolean>
  insertSession(session: SessionRow): Promise<void>
  rotateSession(oldHash: string, now: Date, build: (current: SessionDraft) => SessionRow): Promise<RotateResult>
  revokeFamilyByHash(hash: string, now: Date): Promise<void>
  membership(householdId: string, accountId: string): Promise<MemberRole | null>
}

export interface MemoryRepository extends AuthRepository, HouseholdStore, BoardStore {
  seedMember(householdId: string, accountId: string, role: MemberRole): void
}

function sameEmail(left: string | null, right: string): boolean {
  return (left ?? '').trim().toLowerCase() === right.trim().toLowerCase()
}

export function createMemoryRepository(): MemoryRepository {
  const accounts = new Map<string, AccountRow>()
  const identities: IdentityRow[] = []
  const sessions = new Map<string, SessionRow>()
  const members = new Map<string, Map<string, MemberRole>>()
  const household = createHouseholdMemory(accounts, (householdId, accountId, role) => {
    const rows = members.get(householdId) ?? new Map<string, MemberRole>()
    if (role) rows.set(accountId, role)
    else rows.delete(accountId)
    members.set(householdId, rows)
  })
  const board = createMemoryBoard()

  function requireAccount(id: string): AccountRow {
    const account = accounts.get(id)
    if (!account) throw new AppError('not_found', 404)
    return account
  }

  return {
    async countAccounts() {
      return accounts.size
    },
    async findIdentity(provider, subject) {
      return identities.find((row) => row.provider === provider && row.subject === subject) ?? null
    },
    async findVerifiedEmailMatches(email) {
      return identities.filter(
        (row) => row.emailVerified && !row.isPrivateRelay && sameEmail(row.email, email),
      )
    },
    async listIdentities(accountId) {
      return identities.filter((row) => row.accountId === accountId)
    },
    async getAccount(id) {
      return accounts.get(id) ?? null
    },
    async insertAccountAndIdentity(account, identity) {
      if (identities.some((row) => row.provider === identity.provider && row.subject === identity.subject)) {
        throw new AppError('identity_in_use', 409)
      }
      accounts.set(account.id, { ...account })
      identities.push({ ...identity })
    },
    async updateNamesIfEmpty(accountId, names) {
      const account = requireAccount(accountId)
      if (!account.givenName && !account.familyName && (names.givenName || names.familyName)) {
        account.givenName = names.givenName
        account.familyName = names.familyName
        account.displayName = names.displayName
      }
      return { ...account }
    },
    async insertIdentity(identity) {
      if (identities.some((row) => row.provider === identity.provider && row.subject === identity.subject)) {
        throw new AppError('identity_in_use', 409)
      }
      identities.push({ ...identity })
    },
    async deleteIdentity(accountId, provider) {
      const index = identities.findIndex((row) => row.accountId === accountId && row.provider === provider)
      if (index < 0) return false
      identities.splice(index, 1)
      return true
    },
    async insertSession(session) {
      sessions.set(session.id, { ...session })
    },
    async rotateSession(oldHash, now, build) {
      const current = [...sessions.values()].find((row) => row.refreshTokenHash === oldHash)
      if (!current) return { status: 'missing' }
      if (current.revokedAt) {
        for (const row of sessions.values()) {
          if (row.familyId === current.familyId && !row.revokedAt) row.revokedAt = now
        }
        return { status: 'revoked' }
      }
      if (current.expiresAt.getTime() <= now.getTime()) {
        current.revokedAt = now
        return { status: 'expired' }
      }
      const next = build({ accountId: current.accountId, familyId: current.familyId })
      sessions.set(next.id, { ...next })
      current.revokedAt = now
      current.replacedBy = next.id
      return { status: 'ok', accountId: current.accountId }
    },
    async revokeFamilyByHash(hash, now) {
      const current = [...sessions.values()].find((row) => row.refreshTokenHash === hash)
      if (!current) return
      for (const row of sessions.values()) {
        if (row.familyId === current.familyId && !row.revokedAt) row.revokedAt = now
      }
    },
    async membership(householdId, accountId) {
      return members.get(householdId)?.get(accountId) ?? null
    },
    seedMember(householdId, accountId, role) {
      const rows = members.get(householdId) ?? new Map<string, MemberRole>()
      rows.set(accountId, role)
      members.set(householdId, rows)
    },
    transaction: household.transaction,
    preferenceRetained: household.preferenceRetained,
    boardTransaction: board.boardTransaction,
  }
}
