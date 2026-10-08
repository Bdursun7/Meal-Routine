export interface PreferenceRow {
  householdId: string
  cookingDays: number[]
  maxWeekdayMinutes: number
  preferredCategories: string[]
  preferredProteins: string[]
  avoidedIngredients: string[]
  revision: number
}

export interface ReactionRow {
  id: string
  mealId: string
  accountId: string
  reaction: 'want' | 'okay' | 'veto'
  revision: number
}

export interface MealRow {
  id: string
  planId: string
  dayOffset: number
  recipeSlug: string
  title: string
  recipeOwnerAccountId: string | null
  status: 'proposed' | 'accepted' | 'vetoed' | 'replaced' | 'cooked'
  revision: number
  reactions: ReactionRow[]
}

export interface PlanRow {
  id: string
  householdId: string
  weekStart: string
  status: 'draft' | 'needsDecisions' | 'ready' | 'inProgress' | 'completed'
  isFinalized: boolean
  revision: number
  meals: MealRow[]
}

export interface GroceryRow {
  id: string
  householdId: string
  itemKey: string
  quantity: number
  isChecked: boolean
  updatedBy: string | null
  revision: number
}

export interface ActivityRow {
  id: string
  householdId: string
  actorAccountId: string
  actorName: string
  kind: string
  mealTitle: string
  /** Turkish text kept for pre-V5.1 clients only; current clients render `detailCode`. */
  detail: string
  /** Stable, language-independent activity detail (`ACTIVITY_DETAIL_CODES`). Null on rows written before 0013. */
  detailCode: ActivityDetailCode | null
  createdAt: string
}

export const ACTIVITY_DETAIL_CODES = ['planCreated', 'checked', 'unchecked', 'cooked', 'replaced', 'vetoed', 'reactionUpdated'] as const

export type ActivityDetailCode = (typeof ACTIVITY_DETAIL_CODES)[number]

/** Legacy `detail` text for clients older than V5.1, which display the field verbatim. */
export const LEGACY_ACTIVITY_DETAIL: Readonly<Record<ActivityDetailCode, string>> = Object.freeze({
  planCreated: 'Ortak plan kuruldu',
  checked: 'İşaretlendi',
  unchecked: 'İşaret kalktı',
  cooked: 'Pişti',
  replaced: 'Yemek değişti',
  vetoed: 'Bu hafta olmaz',
  reactionUpdated: 'Tepki güncellendi',
})

export interface ChangeRow {
  cursor: number
  entityType: string
  entityId: string
  operationType: string
  revision: number
  payload: unknown
}

export interface BoardDocument {
  cursor: number
  preference: PreferenceRow
  plans: PlanRow[]
  grocery: GroceryRow[]
  activity: ActivityRow[]
}

export interface IdempotencyHit {
  requestHash: string
  responseStatus: number
  responseBody: unknown
  expiresAt: Date
}

export interface BoardTx {
  readIdempotency(accountId: string, key: string): Promise<IdempotencyHit | null>
  writeIdempotency(row: IdempotencyHit & { accountId: string; key: string }): Promise<void>
  load(householdId: string): Promise<BoardDocument>
  persist(householdId: string, document: BoardDocument, changes: ChangeRow[]): Promise<number>
  changesSince(householdId: string, cursor: number): Promise<{ cursor: number; changes: ChangeRow[] }>
}

export interface BoardStore {
  boardTransaction<T>(work: (tx: BoardTx) => Promise<T>): Promise<T>
}

export function defaultPreference(householdId: string): PreferenceRow {
  return {
    householdId,
    cookingDays: [],
    maxWeekdayMinutes: 60,
    preferredCategories: [],
    preferredProteins: [],
    avoidedIngredients: [],
    revision: 1,
  }
}

export function publicBoard(document: BoardDocument) {
  return {
    cursor: document.cursor,
    preference: {
      cookingDays: document.preference.cookingDays,
      maxWeekdayMinutes: document.preference.maxWeekdayMinutes,
      preferredCategories: document.preference.preferredCategories,
      preferredProteins: document.preference.preferredProteins,
      avoidedIngredients: document.preference.avoidedIngredients,
      revision: document.preference.revision,
    },
    plans: document.plans.map((plan) => ({
      id: plan.id,
      weekStart: plan.weekStart,
      status: plan.status,
      isFinalized: plan.isFinalized,
      revision: plan.revision,
      meals: plan.meals.map((meal) => ({
        id: meal.id,
        dayOffset: meal.dayOffset,
        recipeSlug: meal.recipeSlug,
        title: meal.title,
        recipeOwnerAccountId: meal.recipeOwnerAccountId,
        status: meal.status,
        revision: meal.revision,
        reactions: meal.reactions.map((reaction) => ({
          id: reaction.id,
          accountId: reaction.accountId,
          reaction: reaction.reaction,
          revision: reaction.revision,
        })),
      })),
    })),
    grocery: document.grocery.map((item) => ({
      id: item.id,
      itemKey: item.itemKey,
      quantity: item.quantity,
      isChecked: item.isChecked,
      updatedBy: item.updatedBy,
      revision: item.revision,
    })),
    activity: document.activity.map((row) => ({
      id: row.id,
      actorAccountId: row.actorAccountId,
      actorName: row.actorName,
      kind: row.kind,
      mealTitle: row.mealTitle,
      detail: row.detail,
      detailCode: row.detailCode,
      createdAt: row.createdAt,
    })),
  }
}
