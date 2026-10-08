import type { Pool, PoolClient } from 'pg'
import { AppError } from './errors.js'
import type {
  HouseholdRecord,
  HouseholdStore,
  HouseholdTx,
  InviteRecord,
  InviteStatus,
  MemberRecord,
  MembershipRef,
} from './householdTypes.js'
import type { MeasurementSystem } from './regional.js'
import type { MemberRole } from './repository.js'

export function createPgHouseholdStore(pool: Pool): HouseholdStore {
  return {
    async transaction(work) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        const result = await work(pgTx(client))
        await client.query('COMMIT')
        return result
      } catch (error) {
        await client.query('ROLLBACK')
        throw mapPg(error)
      } finally {
        client.release()
      }
    },
    async preferenceRetained(householdId) {
      const result = await pool.query('SELECT 1 FROM household_preferences WHERE household_id = $1', [householdId])
      return (result.rowCount ?? 0) > 0
    },
  }
}

function pgTx(client: PoolClient): HouseholdTx {
  return {
    async account(id) {
      const result = await client.query<{
        id: string
        display_name: string
        locale: string
        country_code: string
        currency_code: string
        measurement_system: MeasurementSystem
        timezone: string
      }>(
        `SELECT id, display_name, locale, country_code, currency_code, measurement_system, timezone
           FROM accounts WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      )
      const row = result.rows[0]
      if (!row) return null
      return {
        id: row.id,
        displayName: row.display_name,
        settings: {
          locale: row.locale,
          countryCode: row.country_code,
          currencyCode: row.currency_code,
          measurementSystem: row.measurement_system,
          timezone: row.timezone,
        },
      }
    },
    async activeMembership(accountId) {
      const result = await client.query<{ id: string; household_id: string; role: MemberRole }>(
        `SELECT m.id, m.household_id, m.role
           FROM household_members m
           JOIN households h ON h.id = m.household_id
          WHERE m.account_id = $1 AND m.left_at IS NULL AND h.deleted_at IS NULL`,
        [accountId],
      )
      const row = result.rows[0]
      if (!row) return null
      const membership: MembershipRef = { householdId: row.household_id, memberId: row.id, role: row.role }
      return membership
    },
    async household(id) {
      const result = await client.query<{
        id: string
        name: string
        owner_account_id: string
        deleted_at: Date | null
        country_code: string
        currency_code: string
        measurement_system: MeasurementSystem
        timezone: string
      }>(
        `SELECT id, name, owner_account_id, deleted_at, country_code, currency_code, measurement_system, timezone
           FROM households WHERE id = $1`,
        [id],
      )
      const row = result.rows[0]
      if (!row) return null
      const household: HouseholdRecord = {
        id: row.id,
        name: row.name,
        ownerAccountId: row.owner_account_id,
        deletedAt: row.deleted_at,
        settings: {
          countryCode: row.country_code,
          currencyCode: row.currency_code,
          measurementSystem: row.measurement_system,
          timezone: row.timezone,
        },
      }
      return household
    },
    async lockHousehold(id) {
      await client.query('SELECT id FROM households WHERE id = $1 FOR UPDATE', [id])
    },
    async members(householdId) {
      const result = await client.query<{ id: string; account_id: string; role: MemberRole; display_name: string }>(
        `SELECT id, account_id, role, display_name
           FROM household_members
          WHERE household_id = $1 AND left_at IS NULL
          ORDER BY joined_at`,
        [householdId],
      )
      return result.rows.map(
        (row): MemberRecord => ({
          id: row.id,
          householdId,
          accountId: row.account_id,
          role: row.role,
          displayName: row.display_name,
        }),
      )
    },
    async pendingInvites(householdId) {
      const result = await client.query(
        `SELECT id, household_id, created_by, code, status, expires_at, used_at, used_by
           FROM invites
          WHERE household_id = $1 AND status = 'pending'
          ORDER BY created_at`,
        [householdId],
      )
      return result.rows.map((row) => inviteFrom(row))
    },
    async expireInvites(householdId, now) {
      await client.query(
        `UPDATE invites
            SET status = 'expired', revision = revision + 1
          WHERE household_id = $1 AND status = 'pending' AND expires_at <= $2`,
        [householdId, now],
      )
    },
    async insertHousehold(row) {
      await client.query(
        `INSERT INTO households
           (id, name, owner_account_id, created_at, updated_at, country_code, currency_code, measurement_system, timezone)
         VALUES ($1, $2, $3, $4, $4, $5, $6, $7, $8)`,
        [
          row.id,
          row.name,
          row.ownerAccountId,
          row.now,
          row.settings.countryCode,
          row.settings.currencyCode,
          row.settings.measurementSystem,
          row.settings.timezone,
        ],
      )
    },
    async saveHouseholdSettings(id, settings, now) {
      await client.query(
        `UPDATE households
            SET country_code = $2, currency_code = $3, measurement_system = $4, timezone = $5,
                revision = revision + 1, updated_at = $6
          WHERE id = $1 AND deleted_at IS NULL`,
        [id, settings.countryCode, settings.currencyCode, settings.measurementSystem, settings.timezone, now],
      )
    },
    async insertMember(row) {
      await client.query(
        `INSERT INTO household_members (id, household_id, account_id, role, display_name, joined_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [row.id, row.householdId, row.accountId, row.role, row.displayName, row.now],
      )
    },
    async insertPreference(householdId) {
      await client.query(
        'INSERT INTO household_preferences (household_id) VALUES ($1) ON CONFLICT (household_id) DO NOTHING',
        [householdId],
      )
    },
    async rename(id, name, now) {
      await client.query(
        `UPDATE households
            SET name = $2, revision = revision + 1, updated_at = $3
          WHERE id = $1 AND deleted_at IS NULL`,
        [id, name, now],
      )
    },
    async setOwner(householdId, accountId, now) {
      await client.query(
        `UPDATE households
            SET owner_account_id = $2, revision = revision + 1, updated_at = $3
          WHERE id = $1`,
        [householdId, accountId, now],
      )
    },
    async setRole(memberId, role) {
      await client.query(
        `UPDATE household_members
            SET role = $2, revision = revision + 1
          WHERE id = $1 AND left_at IS NULL`,
        [memberId, role],
      )
    },
    async markLeft(memberId, now) {
      await client.query(
        `UPDATE household_members
            SET left_at = $2,
                role = CASE WHEN role = 'owner' THEN 'member' ELSE role END,
                revision = revision + 1
          WHERE id = $1 AND left_at IS NULL`,
        [memberId, now],
      )
    },
    async softDelete(householdId, now) {
      await client.query(
        `UPDATE households
            SET deleted_at = $2, revision = revision + 1, updated_at = $2
          WHERE id = $1 AND deleted_at IS NULL`,
        [householdId, now],
      )
    },
    async cancelPending(householdId) {
      await client.query(
        `UPDATE invites
            SET status = 'cancelled', revision = revision + 1
          WHERE household_id = $1 AND status = 'pending'`,
        [householdId],
      )
    },
    async insertInvite(row) {
      await client.query(
        `INSERT INTO invites (id, household_id, created_by, code, status, expires_at, used_at, used_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [row.id, row.householdId, row.createdBy, row.code, row.status, row.expiresAt, row.usedAt, row.usedBy],
      )
    },
    async lockInviteById(id) {
      const result = await client.query(
        `SELECT id, household_id, created_by, code, status, expires_at, used_at, used_by
           FROM invites WHERE id = $1 FOR UPDATE`,
        [id],
      )
      const row = result.rows[0]
      return row ? inviteFrom(row) : null
    },
    async lockInviteByCode(code) {
      const result = await client.query(
        `SELECT id, household_id, created_by, code, status, expires_at, used_at, used_by
           FROM invites WHERE code = $1 FOR UPDATE`,
        [code],
      )
      const row = result.rows[0]
      return row ? inviteFrom(row) : null
    },
    async saveInvite(row) {
      await client.query(
        `UPDATE invites
            SET status = $2, expires_at = $3, used_at = $4, used_by = $5, revision = revision + 1
          WHERE id = $1`,
        [row.id, row.status, row.expiresAt, row.usedAt, row.usedBy],
      )
    },
  }
}

function inviteFrom(row: {
  id: string
  household_id: string
  created_by: string
  code: string
  status: string
  expires_at: Date
  used_at: Date | null
  used_by: string | null
}): InviteRecord {
  return {
    id: row.id,
    householdId: row.household_id,
    createdBy: row.created_by,
    code: row.code,
    status: row.status as InviteStatus,
    expiresAt: new Date(row.expires_at),
    usedAt: row.used_at ? new Date(row.used_at) : null,
    usedBy: row.used_by,
  }
}

function mapPg(error: unknown): unknown {
  if (error instanceof AppError) return error
  if (!error || typeof error !== 'object' || !('code' in error)) return error
  const code = (error as { code?: string }).code
  const constraint = (error as { constraint?: string }).constraint ?? ''
  if (code === '23514' && constraint === 'households_regional_codes') return new AppError('invalid_request', 400)
  if (code === '23514') return new AppError('household_full', 409)
  if (code === '23505') {
    if (constraint.includes('pending')) return new AppError('duplicate_invite', 409)
    if (constraint.includes('active_household')) return new AppError('already_in_household', 409)
    if (constraint.includes('code')) return new AppError('invite_code_collision', 409)
  }
  return error
}
