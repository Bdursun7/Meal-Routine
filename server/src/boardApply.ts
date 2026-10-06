import { randomUUID } from 'node:crypto'
import { AppError } from './errors.js'
import { isoTimestamp } from './householdTypes.js'
import type { ActivityRow, BoardDocument, ChangeRow, GroceryRow, MealRow, PlanRow } from './boardTypes.js'

const PLAN_STATUS = new Set(['draft', 'needsDecisions', 'ready', 'inProgress', 'completed'])
const MEAL_STATUS = new Set(['proposed', 'accepted', 'vetoed', 'replaced', 'cooked'])
const REACTIONS = new Set(['want', 'okay', 'veto'])

export interface MutationInput {
  entityType: 'grocery' | 'meal' | 'reaction' | 'plan' | 'preference'
  entityId: string
  operationType: 'add' | 'check' | 'replace' | 'set' | 'upsert' | 'update' | 'cook'
  baseRevision: number
  payload: Record<string, unknown>
}

export interface MutationResult {
  cursor: number
  entityType: string
  entityId: string
  revision: number
  entity: unknown
}

export function applyMutation(
  document: BoardDocument,
  input: MutationInput,
  actor: { accountId: string; displayName: string },
  now: Date,
): { document: BoardDocument; result: MutationResult; change: ChangeRow } {
  const next = structuredClone(document)
  let entity: unknown
  let entityType = input.entityType
  let entityId = input.entityId
  let revision = input.baseRevision
  let operationType = input.operationType

  if (input.entityType === 'grocery' && input.operationType === 'add') {
    const itemKey = text(input.payload.itemKey, 'itemKey')
    const quantity = positiveInt(input.payload.quantity ?? 1, 'quantity')
    const existing = next.grocery.find((row) => row.itemKey === itemKey)
    if (!existing) {
      if (input.baseRevision !== 0) conflict('grocery', input.entityId, null)
      const created: GroceryRow = {
        id: uuid(input.entityId),
        householdId: next.preference.householdId,
        itemKey,
        quantity,
        isChecked: false,
        updatedBy: actor.accountId,
        revision: 1,
      }
      next.grocery.push(created)
      entity = publicGrocery(created)
      revision = 1
      entityId = created.id
    } else {
      if (existing.revision !== input.baseRevision) conflict('grocery', existing.id, publicGrocery(existing))
      existing.quantity += quantity
      existing.revision += 1
      existing.updatedBy = actor.accountId
      entity = publicGrocery(existing)
      revision = existing.revision
      entityId = existing.id
    }
  } else if (input.entityType === 'grocery' && input.operationType === 'check') {
    const row = next.grocery.find((item) => item.id === input.entityId)
    if (!row) throw new AppError('not_found', 404)
    if (row.revision !== input.baseRevision) conflict('grocery', row.id, publicGrocery(row))
    row.isChecked = bool(input.payload.isChecked, 'isChecked')
    row.revision += 1
    row.updatedBy = actor.accountId
    entity = publicGrocery(row)
    revision = row.revision
    pushActivity(next, actor, now, 'groceryChecked', row.itemKey, row.isChecked ? 'İşaretlendi' : 'İşaret kalktı')
  } else if (input.entityType === 'meal' && (input.operationType === 'replace' || input.operationType === 'cook')) {
    const meal = findMeal(next, input.entityId)
    if (meal.revision !== input.baseRevision) conflict('meal', meal.id, publicMeal(meal))
    if (input.operationType === 'cook') {
      meal.status = 'cooked'
      pushActivity(next, actor, now, 'mealCooked', meal.title, 'Pişti')
    } else {
      meal.recipeSlug = text(input.payload.recipeSlug, 'recipeSlug')
      meal.title = text(input.payload.title, 'title')
      meal.status = 'replaced'
      pushActivity(next, actor, now, 'replacement', meal.title, 'Yemek değişti')
    }
    meal.revision += 1
    entity = publicMeal(meal)
    revision = meal.revision
  } else if (input.entityType === 'reaction' && input.operationType === 'set') {
    const meal = findMeal(next, input.entityId)
    const mealRevision = input.payload.mealRevision
    if (typeof mealRevision === 'number' && mealRevision !== meal.revision) {
      conflict('meal', meal.id, publicMeal(meal))
    }
    const reactionName = text(input.payload.reaction, 'reaction')
    if (!REACTIONS.has(reactionName)) throw new AppError('invalid_request', 400)
    const current = meal.reactions.find((row) => row.accountId === actor.accountId)
    if (current) {
      if (current.revision !== input.baseRevision) conflict('reaction', meal.id, publicMeal(meal))
      current.reaction = reactionName as 'want' | 'okay' | 'veto'
      current.revision += 1
    } else if (input.baseRevision !== 0) {
      conflict('reaction', meal.id, publicMeal(meal))
    } else {
      meal.reactions.push({
        id: randomUUID(),
        mealId: meal.id,
        accountId: actor.accountId,
        reaction: reactionName as 'want' | 'okay' | 'veto',
        revision: 1,
      })
    }
    if (meal.reactions.some((row) => row.reaction === 'veto')) meal.status = 'vetoed'
    else if (meal.status === 'vetoed') meal.status = 'proposed'
    meal.revision += 1
    entity = publicMeal(meal)
    revision = meal.revision
    entityType = 'meal'
    pushActivity(
      next,
      actor,
      now,
      reactionName === 'veto' ? 'veto' : reactionName,
      meal.title,
      reactionName === 'veto' ? 'Bu hafta olmaz' : 'Tepki güncellendi',
    )
  } else if (input.entityType === 'preference' && input.operationType === 'update') {
    const preference = next.preference
    if (preference.revision !== input.baseRevision) conflict('preference', preference.householdId, publicPreference(preference))
    if (input.payload.cookingDays !== undefined) preference.cookingDays = intList(input.payload.cookingDays)
    if (input.payload.maxWeekdayMinutes !== undefined) {
      preference.maxWeekdayMinutes = positiveInt(input.payload.maxWeekdayMinutes, 'maxWeekdayMinutes')
    }
    if (input.payload.preferredCategories !== undefined) preference.preferredCategories = stringList(input.payload.preferredCategories)
    if (input.payload.preferredProteins !== undefined) preference.preferredProteins = stringList(input.payload.preferredProteins)
    if (input.payload.avoidedIngredients !== undefined) preference.avoidedIngredients = stringList(input.payload.avoidedIngredients)
    preference.revision += 1
    entity = publicPreference(preference)
    revision = preference.revision
    entityId = preference.householdId
  } else if (input.entityType === 'plan' && input.operationType === 'upsert') {
    const weekStart = dateText(input.payload.weekStart)
    const status = text(input.payload.status, 'status')
    if (!PLAN_STATUS.has(status)) throw new AppError('invalid_request', 400)
    let plan = next.plans.find((row) => row.id === input.entityId)
    if (!plan) {
      if (input.baseRevision !== 0) conflict('plan', input.entityId, null)
      plan = {
        id: uuid(input.entityId),
        householdId: next.preference.householdId,
        weekStart,
        status: status as PlanRow['status'],
        isFinalized: bool(input.payload.isFinalized ?? false, 'isFinalized'),
        revision: 1,
        meals: mealsFrom(input.payload.meals, uuid(input.entityId)),
      }
      next.plans.push(plan)
      pushActivity(next, actor, now, 'planGenerated', weekStart, 'Ortak plan kuruldu')
    } else {
      if (plan.revision !== input.baseRevision) conflict('plan', plan.id, publicPlan(plan))
      plan.weekStart = weekStart
      plan.status = status as PlanRow['status']
      plan.isFinalized = bool(input.payload.isFinalized ?? plan.isFinalized, 'isFinalized')
      plan.revision += 1
    }
    entity = publicPlan(plan)
    revision = plan.revision
    entityId = plan.id
  } else {
    throw new AppError('invalid_request', 400)
  }

  const change: ChangeRow = {
    cursor: 0,
    entityType,
    entityId,
    operationType,
    revision,
    payload: entity,
  }
  return {
    document: next,
    change,
    result: { cursor: 0, entityType, entityId, revision, entity },
  }
}

function findMeal(document: BoardDocument, mealId: string): MealRow {
  for (const plan of document.plans) {
    const meal = plan.meals.find((row) => row.id === mealId)
    if (meal) return meal
  }
  throw new AppError('not_found', 404)
}

function mealsFrom(value: unknown, planId: string): MealRow[] {
  if (value === undefined) return []
  if (!Array.isArray(value)) throw new AppError('invalid_request', 400)
  return value.map((raw) => {
    if (!raw || typeof raw !== 'object') throw new AppError('invalid_request', 400)
    const meal = raw as Record<string, unknown>
    const status = meal.status === undefined ? 'proposed' : text(meal.status, 'status')
    if (!MEAL_STATUS.has(status)) throw new AppError('invalid_request', 400)
    return {
      id: uuid(text(meal.id, 'id')),
      planId,
      dayOffset: intIn(meal.dayOffset, 0, 6),
      recipeSlug: text(meal.recipeSlug, 'recipeSlug'),
      title: text(meal.title, 'title'),
      recipeOwnerAccountId: meal.recipeOwnerAccountId ? uuid(text(meal.recipeOwnerAccountId, 'recipeOwnerAccountId')) : null,
      status: status as MealRow['status'],
      revision: 1,
      reactions: [],
    }
  })
}

function pushActivity(
  document: BoardDocument,
  actor: { accountId: string; displayName: string },
  now: Date,
  kind: string,
  mealTitle: string,
  detail: string,
) {
  const row: ActivityRow = {
    id: randomUUID(),
    householdId: document.preference.householdId,
    actorAccountId: actor.accountId,
    actorName: actor.displayName,
    kind,
    mealTitle,
    detail,
    createdAt: isoTimestamp(now),
  }
  document.activity.unshift(row)
  document.activity = document.activity.slice(0, 40)
}

function conflict(entityType: string, entityId: string, server: unknown): never {
  throw new AppError('version_conflict', 409, undefined, { entityType, entityId, server })
}

function publicGrocery(row: GroceryRow) {
  return {
    id: row.id,
    itemKey: row.itemKey,
    quantity: row.quantity,
    isChecked: row.isChecked,
    updatedBy: row.updatedBy,
    revision: row.revision,
  }
}

function publicMeal(meal: MealRow) {
  return {
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
  }
}

function publicPlan(plan: PlanRow) {
  return {
    id: plan.id,
    weekStart: plan.weekStart,
    status: plan.status,
    isFinalized: plan.isFinalized,
    revision: plan.revision,
    meals: plan.meals.map(publicMeal),
  }
}

function publicPreference(row: BoardDocument['preference']) {
  return {
    cookingDays: row.cookingDays,
    maxWeekdayMinutes: row.maxWeekdayMinutes,
    preferredCategories: row.preferredCategories,
    preferredProteins: row.preferredProteins,
    avoidedIngredients: row.avoidedIngredients,
    revision: row.revision,
  }
}

function text(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '' || value.length > 200) throw new AppError('invalid_request', 400)
  void field
  return value.trim()
}

function dateText(value: unknown): string {
  const raw = text(value, 'weekStart')
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) throw new AppError('invalid_request', 400)
  return raw
}

function positiveInt(value: unknown, field: string): number {
  void field
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1 || value > 999) {
    throw new AppError('invalid_request', 400)
  }
  return value
}

function bool(value: unknown, field: string): boolean {
  void field
  if (typeof value !== 'boolean') throw new AppError('invalid_request', 400)
  return value
}

function intIn(value: unknown, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw new AppError('invalid_request', 400)
  }
  return value
}

function intList(value: unknown): number[] {
  if (!Array.isArray(value)) throw new AppError('invalid_request', 400)
  return value.map((item) => intIn(item, 0, 6))
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) throw new AppError('invalid_request', 400)
  return value.map((item) => text(item, 'item'))
}

function uuid(value: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    throw new AppError('invalid_request', 400)
  }
  return value.toLowerCase()
}
