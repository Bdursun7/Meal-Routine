import type { HouseholdService } from './householdService.js'
import type { HouseholdStore } from './householdTypes.js'
import { AppError } from './errors.js'
import type { MigrationStore } from './migrationService.js'
import type { NotificationStore } from './notifications.js'
import type { PantryStore } from './pantryTypes.js'
import type { AuthRepository } from './repository.js'
import { accountRegional, type HouseholdRegionalSettings } from './regional.js'

export type HouseholdOutcome = 'none' | 'left' | 'deleted'

export interface PrivacyService {
  exportAccount(accountId: string): Promise<Record<string, unknown>>
  deleteAccount(accountId: string): Promise<{ deleted: true; household: HouseholdOutcome }>
}

export function createPrivacyService(input: {
  repo: AuthRepository & HouseholdStore
  households: HouseholdService
  migration: MigrationStore
  notifications: NotificationStore
  pantry: PantryStore
  now?: () => Date
}): PrivacyService {
  const now = input.now ?? (() => new Date())

  return {
    async exportAccount(accountId) {
      const account = await input.repo.getAccount(accountId)
      if (!account) throw new AppError('not_found', 404)
      const identities = await input.repo.listIdentities(accountId)
      const personal = await input.migration.load(accountId)
      const preferences = await input.notifications.preferences(accountId)
      const membership = await input.repo.transaction(async (tx) => tx.activeMembership(accountId))
      let household: { id: string; name: string; role: string; settings: HouseholdRegionalSettings } | null = null
      if (membership) {
        const row = await input.repo.transaction(async (tx) => tx.household(membership.householdId))
        if (row && !row.deletedAt) {
          household = { id: row.id, name: row.name, role: membership.role, settings: { ...row.settings } }
        }
      }
      return {
        exportedAt: now().toISOString(),
        account: {
          id: account.id,
          displayName: account.displayName,
          givenName: account.givenName,
          familyName: account.familyName,
        },
        settings: accountRegional(account),
        identities: identities.map((row) => ({
          provider: row.provider,
          email: row.email,
          isPrivateRelay: row.isPrivateRelay,
        })),
        personal: personal.bundle,
        household,
        notificationPreferences: preferences,
        pantry: membership && household ? await input.pantry.listPantry(membership.householdId) : [],
        pantryIngredients: membership && household ? await input.pantry.listIngredients(membership.householdId) : [],
      }
    },

    async deleteAccount(accountId) {
      const account = await input.repo.getAccount(accountId)
      if (!account) throw new AppError('not_found', 404)
      const membership = await input.repo.transaction(async (tx) => tx.activeMembership(accountId))
      const householdId = membership?.householdId ?? null
      let household: HouseholdOutcome = 'none'
      if (membership) {
        const members = await input.repo.transaction(async (tx) => tx.members(membership.householdId))
        if (members.length <= 1) {
          if (membership.role === 'owner') {
            await input.households.deleteHousehold(accountId, membership.householdId)
          } else {
            await input.households.leave(accountId, membership.householdId)
            await input.repo.transaction(async (tx) => {
              await tx.lockHousehold(membership.householdId)
              await tx.cancelPending(membership.householdId)
              await tx.softDelete(membership.householdId, now())
            })
          }
          household = 'deleted'
        } else {
          await input.households.leave(accountId, membership.householdId)
          household = 'left'
        }
      }
      await input.migration.erase(accountId)
      await input.notifications.revokeAllTokens(accountId)
      await input.pantry.clearAccountPantry(accountId)
      if (household === 'deleted' && householdId) await input.pantry.deleteHouseholdPantry(householdId)
      await input.repo.closeAccount(accountId, household, now())
      return { deleted: true, household }
    },
  }
}
