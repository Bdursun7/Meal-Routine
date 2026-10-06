import { createHash } from 'node:crypto'
import { z } from 'zod'
import { AppError } from './errors.js'
import type { PersonalBundle } from './migrationRules.js'
import { emptyBundle, mergeBundle } from './migrationRules.js'

export interface MigrationCounts {
  recipes: number
  memories: number
  favorites: number
  history: number
  feedback: number
}

export interface MigrationStatus {
  status: 'not_started' | 'uploaded' | 'confirmed'
  counts: MigrationCounts
}

export interface MigrationStore {
  load(accountId: string): Promise<{ bundle: PersonalBundle; status: MigrationStatus['status'] }>
  save(accountId: string, bundle: PersonalBundle, status: MigrationStatus['status']): Promise<void>
  claimHistory(accountId: string, ids: string[]): Promise<Set<string>>
  claimFeedback(accountId: string, ids: string[]): Promise<Set<string>>
}

export function createMigrationService(store: MigrationStore) {
  return {
    async upload(accountId: string, incoming: PersonalBundle): Promise<MigrationStatus> {
      const current = await store.load(accountId)
      const owned = assignOwnedIds(accountId, incoming)
      const historyIds = await store.claimHistory(accountId, owned.history.map((row) => row.id))
      const feedbackIds = await store.claimFeedback(accountId, incoming.feedback.map((row) => row.id))
      const safe = {
        ...owned,
        history: owned.history.filter((row) => historyIds.has(row.id)),
        feedback: owned.feedback.filter((row) => feedbackIds.has(row.id)),
      }
      const merged = mergeBundle(current.bundle, safe)
      const status = current.status === 'confirmed' ? 'confirmed' : 'uploaded'
      await store.save(accountId, merged, status)
      return { status, counts: countsOf(merged) }
    },
    async confirm(accountId: string): Promise<MigrationStatus> {
      const current = await store.load(accountId)
      await store.save(accountId, current.bundle, 'confirmed')
      return { status: 'confirmed', counts: countsOf(current.bundle) }
    },
    async status(accountId: string): Promise<MigrationStatus> {
      const current = await store.load(accountId)
      return { status: current.status, counts: countsOf(current.bundle) }
    },
  }
}

const stamp = z.string().min(4).max(40)
const text = z.string().max(2000)
const short = z.string().max(200)

const uploadBody = z.object({
  ownerAccountId: z.string().optional(),
  preferences: z.object({
    updatedAt: stamp,
    householdSize: z.number().int().min(1).max(20),
    eveningsPerWeek: z.number().int().min(1).max(14),
    maxCookMinutes: z.number().int().min(1).max(600),
    dislikedIngredientIds: z.array(short).max(200),
    discoveryLevel: short,
    repeatPreference: short,
    difficultyPreference: short,
    weekdayStyle: short,
    dismissedPatternIds: z.array(short).max(200),
    hasCompletedOnboarding: z.boolean(),
  }).nullable().optional(),
  recipes: z.array(z.object({
    id: z.string().uuid(),
    slug: short.min(1),
    updatedAt: stamp,
    nameTr: text,
    nameEn: text,
    summaryTr: text,
    origin: short,
    collectionState: short,
    sourceUrl: text,
    sourceKey: short,
    sourcePlatform: short,
    sourceTitle: text,
    userNotes: text,
    baseServings: z.number().int().min(0).max(100),
    prepMinutes: z.number().int().min(0).max(2000),
    cookMinutes: z.number().int().min(0).max(2000),
    totalMinutes: z.number().int().min(0).max(4000),
    timeIsUnknown: z.boolean(),
    servingsUnspecified: z.boolean(),
    difficulty: short,
    category: short,
    country: short,
    diets: z.array(short).max(20),
    tags: z.array(short).max(40),
    photoUrl: text,
    ingredients: z.array(z.object({
      id: z.string().uuid(),
      sortIndex: z.number().int().min(0).max(500),
      ingredientId: short,
      nameTr: short,
      nameEn: short,
      quantity: z.number().nullable(),
      unit: short,
      noteTr: text,
      isOptional: z.boolean(),
      includeInGrocery: z.boolean(),
    })).max(80),
    steps: z.array(z.object({
      id: z.string().uuid(),
      sortIndex: z.number().int().min(0).max(200),
      textTr: text,
      textEn: text,
      minutes: z.number().int().nullable(),
    })).max(80),
  })).max(400),
  memories: z.array(z.object({
    recipeSlug: short.min(1),
    updatedAt: stamp,
    timesCooked: z.number().int().nonnegative(),
    timesReplaced: z.number().int().nonnegative(),
    timesSkipped: z.number().int().nonnegative(),
    lastCookedAt: stamp.nullable(),
    lastSelectedAt: stamp.nullable(),
    lovedCount: z.number().int().nonnegative(),
    okayCount: z.number().int().nonnegative(),
    latestRating: short,
    neverAgain: z.boolean(),
    timeConcernCount: z.number().int().nonnegative(),
    difficultyConcernCount: z.number().int().nonnegative(),
    portionConcernCount: z.number().int().nonnegative(),
    missingIngredientCount: z.number().int().nonnegative(),
    tooManyIngredientCount: z.number().int().nonnegative(),
    wouldMakeAgainCount: z.number().int().nonnegative(),
    isFavorite: z.boolean(),
    discoveryStatus: short,
    confidence: short,
  })).max(2000),
  favorites: z.array(z.object({
    recipeSlug: short.min(1),
    createdAt: stamp,
  })).max(2000),
  history: z.array(z.object({
    id: z.string().uuid(),
    recipeSlug: short.min(1),
    eventType: short,
    planWeekId: z.string().uuid().nullable(),
    plannedMealId: z.string().uuid().nullable(),
    replacementReason: text,
    createdAt: stamp,
  })).max(5000),
  feedback: z.array(z.object({
    id: z.string().uuid(),
    recipeSlug: short.min(1),
    rating: short,
    cooked: z.boolean(),
    reasons: z.array(short).max(20),
    createdAt: stamp,
  })).max(5000),
})

export function parseUpload(body: unknown): PersonalBundle {
  const parsed = uploadBody.safeParse(body)
  if (!parsed.success) throw new AppError('invalid_request', 400)
  const value = parsed.data
  return mergeBundle(emptyBundle(), {
    preferences: value.preferences ?? null,
    recipes: value.recipes,
    memories: value.memories,
    favorites: value.favorites,
    history: value.history,
    feedback: value.feedback,
  })
}

export function ownedRecipeID(accountId: string, slug: string): string {
  return stableUUID(`${accountId}:recipe:${slug}`)
}

function assignOwnedIds(accountId: string, bundle: PersonalBundle): PersonalBundle {
  return {
    ...bundle,
    recipes: bundle.recipes.map((recipe) => {
      const id = ownedRecipeID(accountId, recipe.slug)
      return {
        ...recipe,
        id,
        ingredients: recipe.ingredients.map((line) => ({
          ...line,
          id: stableUUID(`${id}:ingredient:${line.sortIndex}`),
        })),
        steps: recipe.steps.map((step) => ({
          ...step,
          id: stableUUID(`${id}:step:${step.sortIndex}`),
        })),
      }
    }),
  }
}

function stableUUID(value: string): string {
  const bytes = createHash('sha256').update(value).digest().subarray(0, 16)
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = bytes.toString('hex')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export function countsOf(bundle: PersonalBundle): MigrationCounts {
  return {
    recipes: bundle.recipes.length,
    memories: bundle.memories.length,
    favorites: bundle.favorites.length,
    history: bundle.history.length,
    feedback: bundle.feedback.length,
  }
}
