import type { PersonalBundle } from './migrationRules.js'
import { emptyBundle } from './migrationRules.js'
import type { MigrationStore } from './migrationService.js'

export function createMemoryMigration(): MigrationStore {
  const bundles = new Map<string, PersonalBundle>()
  const statuses = new Map<string, 'not_started' | 'uploaded' | 'confirmed'>()
  const historyOwner = new Map<string, string>()
  const feedbackOwner = new Map<string, string>()

  return {
    async load(accountId) {
      return {
        bundle: structuredClone(bundles.get(accountId) ?? emptyBundle()),
        status: statuses.get(accountId) ?? 'not_started',
      }
    },
    async save(accountId, bundle, status) {
      bundles.set(accountId, structuredClone(bundle))
      statuses.set(accountId, status)
      for (const row of bundle.history) historyOwner.set(row.id, accountId)
      for (const row of bundle.feedback) feedbackOwner.set(row.id, accountId)
    },
    async claimHistory(accountId, ids) {
      return claim(historyOwner, accountId, ids)
    },
    async claimFeedback(accountId, ids) {
      return claim(feedbackOwner, accountId, ids)
    },
  }
}

function claim(owners: Map<string, string>, accountId: string, ids: string[]): Set<string> {
  const allowed = new Set<string>()
  for (const id of ids) {
    const owner = owners.get(id)
    if (!owner || owner === accountId) allowed.add(id)
  }
  return allowed
}
