import { randomUUID } from 'node:crypto'
import type { Pool } from 'pg'
import type { BoardStore } from './boardTypes.js'
import { AppError } from './errors.js'
import { createPgBoard } from './pgBoard.js'
import { createPgHouseholdStore } from './pgHousehold.js'
import type {
  AccountRow,
  AuthRepository,
  IdentityRow,
  MemberRole,
  ProviderName,
  RotateResult,
  SessionDraft,
  SessionRow,
} from './repository.js'
import type { HouseholdStore } from './householdTypes.js'

function asProvider(value: string): ProviderName {
  if (value === 'apple' || value === 'google' || value === 'dev') return value
  throw new AppError('invalid_request', 400)
}

function accountFrom(row: {
  id: string
  display_name: string
  given_name: string
  family_name: string
  created_at: Date
}): AccountRow {
  return {
    id: row.id,
    displayName: row.display_name,
    givenName: row.given_name,
    familyName: row.family_name,
    createdAt: new Date(row.created_at),
  }
}

function identityFrom(row: {
  id: string
  account_id: string
  provider: string
  subject: string
  email: string | null
  email_verified: boolean
  is_private_relay: boolean
}): IdentityRow {
  return {
    id: row.id,
    accountId: row.account_id,
    provider: asProvider(row.provider),
    subject: row.subject,
    email: row.email,
    emailVerified: row.email_verified,
    isPrivateRelay: row.is_private_relay,
  }
}

export function createPgRepository(pool: Pool): AuthRepository & HouseholdStore & BoardStore {
  const household = createPgHouseholdStore(pool)
  const board = createPgBoard(pool)
  return {
    async countAccounts() {
      const result = await pool.query<{ count: string }>('SELECT COUNT(*)::text AS count FROM accounts')
      return Number(result.rows[0]?.count ?? 0)
    },
    async findIdentity(provider, subject) {
      const result = await pool.query(
        `SELECT id, account_id, provider, subject, email, email_verified, is_private_relay
           FROM auth_identities WHERE provider = $1 AND subject = $2`,
        [provider, subject],
      )
      const row = result.rows[0]
      return row ? identityFrom(row) : null
    },
    async findVerifiedEmailMatches(email) {
      const result = await pool.query(
        `SELECT id, account_id, provider, subject, email, email_verified, is_private_relay
           FROM auth_identities
          WHERE email_verified = TRUE
            AND is_private_relay = FALSE
            AND lower(email) = lower($1)`,
        [email],
      )
      return result.rows.map((row) => identityFrom(row))
    },
    async listIdentities(accountId) {
      const result = await pool.query(
        `SELECT id, account_id, provider, subject, email, email_verified, is_private_relay
           FROM auth_identities WHERE account_id = $1 ORDER BY created_at`,
        [accountId],
      )
      return result.rows.map((row) => identityFrom(row))
    },
    async getAccount(id) {
      const result = await pool.query(
        `SELECT id, display_name, given_name, family_name, created_at
           FROM accounts WHERE id = $1 AND deleted_at IS NULL`,
        [id],
      )
      const row = result.rows[0]
      return row ? accountFrom(row) : null
    },
    async insertAccountAndIdentity(account, identity) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        await client.query(
          `INSERT INTO accounts (id, display_name, given_name, family_name, created_at)
           VALUES ($1, $2, $3, $4, $5)`,
          [account.id, account.displayName, account.givenName, account.familyName, account.createdAt],
        )
        await client.query(
          `INSERT INTO auth_identities
             (id, account_id, provider, subject, email, email_verified, is_private_relay)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            identity.id,
            identity.accountId,
            identity.provider,
            identity.subject,
            identity.email,
            identity.emailVerified,
            identity.isPrivateRelay,
          ],
        )
        await client.query('COMMIT')
      } catch (error) {
        await client.query('ROLLBACK')
        throw mapUnique(error)
      } finally {
        client.release()
      }
    },
    async updateNamesIfEmpty(accountId, names) {
      const result = await pool.query(
        `UPDATE accounts
            SET given_name = $2,
                family_name = $3,
                display_name = $4,
                updated_at = now()
          WHERE id = $1
            AND given_name = ''
            AND family_name = ''
            AND ($2 <> '' OR $3 <> '')
        RETURNING id, display_name, given_name, family_name, created_at`,
        [accountId, names.givenName, names.familyName, names.displayName],
      )
      if (result.rows[0]) return accountFrom(result.rows[0])
      const current = await pool.query(
        `SELECT id, display_name, given_name, family_name, created_at FROM accounts WHERE id = $1`,
        [accountId],
      )
      if (!current.rows[0]) throw new AppError('not_found', 404)
      return accountFrom(current.rows[0])
    },
    async insertIdentity(identity) {
      try {
        await pool.query(
          `INSERT INTO auth_identities
             (id, account_id, provider, subject, email, email_verified, is_private_relay)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            identity.id,
            identity.accountId,
            identity.provider,
            identity.subject,
            identity.email,
            identity.emailVerified,
            identity.isPrivateRelay,
          ],
        )
      } catch (error) {
        throw mapUnique(error)
      }
    },
    async deleteIdentity(accountId, provider) {
      const result = await pool.query(
        `DELETE FROM auth_identities WHERE account_id = $1 AND provider = $2`,
        [accountId, provider],
      )
      return (result.rowCount ?? 0) > 0
    },
    async insertSession(session) {
      await pool.query(
        `INSERT INTO sessions (id, account_id, family_id, refresh_token_hash, expires_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [session.id, session.accountId, session.familyId, session.refreshTokenHash, session.expiresAt],
      )
    },
    async rotateSession(oldHash, now, build) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        const found = await client.query<{
          id: string
          account_id: string
          family_id: string
          expires_at: Date
          revoked_at: Date | null
        }>(
          `SELECT id, account_id, family_id, expires_at, revoked_at
             FROM sessions WHERE refresh_token_hash = $1 FOR UPDATE`,
          [oldHash],
        )
        const row = found.rows[0]
        if (!row) {
          await client.query('ROLLBACK')
          return { status: 'missing' }
        }
        if (row.revoked_at) {
          await client.query(
            `UPDATE sessions SET revoked_at = $2 WHERE family_id = $1 AND revoked_at IS NULL`,
            [row.family_id, now],
          )
          await client.query('COMMIT')
          return { status: 'revoked' }
        }
        if (new Date(row.expires_at).getTime() <= now.getTime()) {
          await client.query(`UPDATE sessions SET revoked_at = $2 WHERE id = $1`, [row.id, now])
          await client.query('COMMIT')
          return { status: 'expired' }
        }
        const next = build({ accountId: row.account_id, familyId: row.family_id })
        await client.query(
          `INSERT INTO sessions (id, account_id, family_id, refresh_token_hash, expires_at)
           VALUES ($1, $2, $3, $4, $5)`,
          [next.id, next.accountId, next.familyId, next.refreshTokenHash, next.expiresAt],
        )
        await client.query(`UPDATE sessions SET revoked_at = $2, replaced_by = $3 WHERE id = $1`, [
          row.id,
          now,
          next.id,
        ])
        await client.query('COMMIT')
        return { status: 'ok', accountId: row.account_id }
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      } finally {
        client.release()
      }
    },
    async revokeFamilyByHash(hash, now) {
      await pool.query(
        `UPDATE sessions
            SET revoked_at = $2
          WHERE family_id = (
            SELECT family_id FROM sessions WHERE refresh_token_hash = $1
          )
            AND revoked_at IS NULL`,
        [hash, now],
      )
    },
    async closeAccount(accountId, householdOutcome, now) {
      const client = await pool.connect()
      try {
        await client.query('BEGIN')
        await client.query(
          `UPDATE sessions SET revoked_at = $2 WHERE account_id = $1 AND revoked_at IS NULL`,
          [accountId, now],
        )
        await client.query(`DELETE FROM auth_identities WHERE account_id = $1`, [accountId])
        await client.query(
          `UPDATE accounts
              SET display_name = '', given_name = '', family_name = '', deleted_at = $2, updated_at = $2
            WHERE id = $1 AND deleted_at IS NULL`,
          [accountId, now],
        )
        await client.query(
          `INSERT INTO account_deletions (id, account_id, deleted_at, household_outcome)
           VALUES ($1, $2, $3, $4)`,
          [randomUUID(), accountId, now, householdOutcome],
        )
        await client.query('COMMIT')
      } catch (error) {
        await client.query('ROLLBACK')
        throw error
      } finally {
        client.release()
      }
    },
    async membership(householdId, accountId) {
      const result = await pool.query<{ role: MemberRole }>(
        `SELECT m.role
           FROM household_members m
           JOIN households h ON h.id = m.household_id
          WHERE m.household_id = $1
            AND m.account_id = $2
            AND m.left_at IS NULL
            AND h.deleted_at IS NULL`,
        [householdId, accountId],
      )
      return result.rows[0]?.role ?? null
    },
    transaction: household.transaction,
    preferenceRetained: household.preferenceRetained,
    boardTransaction: board.boardTransaction,
  }
}

function mapUnique(error: unknown): unknown {
  if (error && typeof error === 'object' && 'code' in error && (error as { code?: string }).code === '23505') {
    return new AppError('identity_in_use', 409)
  }
  return error
}

export type { SessionRow, SessionDraft }
