import type { MemberRole } from './repository.js'

export type InviteStatus = 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'expired'

export interface AccountRef {
  id: string
  displayName: string
}

export interface HouseholdRecord {
  id: string
  name: string
  ownerAccountId: string
  deletedAt: Date | null
}

export interface MemberRecord {
  id: string
  householdId: string
  accountId: string
  role: MemberRole
  displayName: string
}

export interface InviteRecord {
  id: string
  householdId: string
  createdBy: string
  code: string
  status: InviteStatus
  expiresAt: Date
  usedAt: Date | null
  usedBy: string | null
}

export interface MembershipRef {
  householdId: string
  memberId: string
  role: MemberRole
}

export interface HouseholdTx {
  account(id: string): Promise<AccountRef | null>
  activeMembership(accountId: string): Promise<MembershipRef | null>
  household(id: string): Promise<HouseholdRecord | null>
  lockHousehold(id: string): Promise<void>
  members(householdId: string): Promise<MemberRecord[]>
  pendingInvites(householdId: string): Promise<InviteRecord[]>
  expireInvites(householdId: string, now: Date): Promise<void>
  insertHousehold(row: { id: string; name: string; ownerAccountId: string; now: Date }): Promise<void>
  insertMember(row: MemberRecord & { now: Date }): Promise<void>
  insertPreference(householdId: string): Promise<void>
  rename(id: string, name: string, now: Date): Promise<void>
  setOwner(householdId: string, accountId: string, now: Date): Promise<void>
  setRole(memberId: string, role: MemberRole): Promise<void>
  markLeft(memberId: string, now: Date): Promise<void>
  softDelete(householdId: string, now: Date): Promise<void>
  cancelPending(householdId: string): Promise<void>
  insertInvite(row: InviteRecord): Promise<void>
  lockInviteById(id: string): Promise<InviteRecord | null>
  lockInviteByCode(code: string): Promise<InviteRecord | null>
  saveInvite(row: InviteRecord): Promise<void>
}

export interface HouseholdStore {
  transaction<T>(work: (tx: HouseholdTx) => Promise<T>): Promise<T>
  preferenceRetained(householdId: string): Promise<boolean>
}

export interface PublicMember {
  accountId: string
  displayName: string
  role: MemberRole
}

export interface PublicInvite {
  id: string
  code: string
  status: InviteStatus
  expiresAt: string
}

export interface PublicHousehold {
  id: string
  name: string
  role: MemberRole
  members: PublicMember[]
  invites: PublicInvite[]
}

export interface HouseholdBody {
  household: PublicHousehold | null
}

export const INVITE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000
export const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

export function isoTimestamp(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

export function normalizeInviteCode(raw: string): string {
  const allowed = new Set(INVITE_ALPHABET)
  return raw
    .toUpperCase()
    .split('')
    .filter((character) => allowed.has(character))
    .join('')
}
