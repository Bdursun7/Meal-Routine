import { createHash } from 'node:crypto'
import { AppError } from './errors.js'
import { applyMutation, type MutationInput, type MutationResult } from './boardApply.js'
import { publicBoard, type BoardStore } from './boardTypes.js'
import type { HouseholdStore } from './householdTypes.js'

const IDEMPOTENCY_MS = 24 * 60 * 60 * 1000

export interface BoardService {
  board(accountId: string, householdId: string): Promise<ReturnType<typeof publicBoard>>
  changes(accountId: string, householdId: string, cursor: number): Promise<{ cursor: number; changes: unknown[] }>
  mutate(
    accountId: string,
    householdId: string,
    idempotencyKey: string,
    input: MutationInput,
  ): Promise<MutationResult>
}

export function createBoardService(
  households: HouseholdStore,
  boards: BoardStore,
  now: () => Date = () => new Date(),
): BoardService {
  return {
    async board(accountId, householdId) {
      await authorize(households, householdId, accountId)
      return boards.boardTransaction(async (tx) => publicBoard(await tx.load(householdId)))
    },
    async changes(accountId, householdId, cursor) {
      await authorize(households, householdId, accountId)
      return boards.boardTransaction(async (tx) => tx.changesSince(householdId, cursor))
    },
    async mutate(accountId, householdId, idempotencyKey, input) {
      const actor = await authorize(households, householdId, accountId)
      const clock = now()
      const requestHash = hashBody(input)
      return boards.boardTransaction(async (tx) => {
        const existing = await tx.readIdempotency(accountId, idempotencyKey)
        if (existing && existing.expiresAt.getTime() > clock.getTime()) {
          if (existing.requestHash !== requestHash) throw new AppError('idempotency_key_reused', 409)
          return existing.responseBody as MutationResult
        }
        const document = await tx.load(householdId)
        const applied = applyMutation(document, input, actor, clock)
        const cursor = await tx.persist(householdId, applied.document, [applied.change])
        applied.result.cursor = cursor
        await tx.writeIdempotency({
          accountId,
          key: idempotencyKey,
          requestHash,
          responseStatus: 200,
          responseBody: applied.result,
          expiresAt: new Date(clock.getTime() + IDEMPOTENCY_MS),
        })
        return applied.result
      })
    },
  }
}

async function authorize(households: HouseholdStore, householdId: string, accountId: string) {
  return households.transaction(async (tx) => {
    const household = await tx.household(householdId)
    if (!household || household.deletedAt) throw new AppError('not_found', 404)
    const members = await tx.members(householdId)
    const me = members.find((member) => member.accountId === accountId)
    if (!me) throw new AppError('forbidden', 403)
    return { accountId, displayName: me.displayName }
  })
}

function hashBody(input: MutationInput): string {
  return createHash('sha256').update(stable(input)).digest('hex')
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`
  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>).sort(([left], [right]) => left.localeCompare(right))
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(',')}}`
  }
  return JSON.stringify(value) ?? 'null'
}
