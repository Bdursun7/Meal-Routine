import type { BoardDocument, BoardStore, BoardTx, ChangeRow, IdempotencyHit } from './boardTypes.js'
import { defaultPreference } from './boardTypes.js'

interface StoredBoard {
  document: BoardDocument
  changes: ChangeRow[]
}

export function createMemoryBoard(): BoardStore {
  const boards = new Map<string, StoredBoard>()
  const idempotency = new Map<string, IdempotencyHit & { accountId: string; key: string }>()
  let globalCursor = 0

  const tx: BoardTx = {
    async readIdempotency(accountId, key) {
      const row = idempotency.get(`${accountId}:${key}`)
      return row ? { ...row, responseBody: structuredClone(row.responseBody) } : null
    },
    async writeIdempotency(row) {
      idempotency.set(`${row.accountId}:${row.key}`, {
        ...row,
        responseBody: structuredClone(row.responseBody),
      })
    },
    async load(householdId) {
      const stored = boards.get(householdId)
      if (!stored) {
        return {
          cursor: 0,
          preference: defaultPreference(householdId),
          plans: [],
          grocery: [],
          activity: [],
        }
      }
      return structuredClone(stored.document)
    },
    async persist(householdId, document, changes) {
      const stored = boards.get(householdId) ?? { document, changes: [] }
      for (const change of changes) {
        globalCursor += 1
        change.cursor = globalCursor
        document.cursor = globalCursor
        stored.changes.push(structuredClone(change))
      }
      stored.document = structuredClone(document)
      boards.set(householdId, stored)
      return document.cursor
    },
    async changesSince(householdId, cursor) {
      const stored = boards.get(householdId)
      const changes = (stored?.changes ?? []).filter((change) => change.cursor > cursor)
      return { cursor: stored?.document.cursor ?? 0, changes: structuredClone(changes) }
    },
  }

  return {
    async boardTransaction(work) {
      return work(tx)
    },
  }
}
