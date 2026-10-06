export interface MigrationIngredient {
  id: string
  sortIndex: number
  ingredientId: string
  nameTr: string
  nameEn: string
  quantity: number | null
  unit: string
  noteTr: string
  isOptional: boolean
  includeInGrocery: boolean
}

export interface MigrationStep {
  id: string
  sortIndex: number
  textTr: string
  textEn: string
  minutes: number | null
}

export interface MigrationRecipe {
  id: string
  slug: string
  updatedAt: string
  nameTr: string
  nameEn: string
  summaryTr: string
  origin: string
  collectionState: string
  sourceUrl: string
  sourceKey: string
  sourcePlatform: string
  sourceTitle: string
  userNotes: string
  baseServings: number
  prepMinutes: number
  cookMinutes: number
  totalMinutes: number
  timeIsUnknown: boolean
  servingsUnspecified: boolean
  difficulty: string
  category: string
  country: string
  diets: string[]
  tags: string[]
  photoUrl: string
  ingredients: MigrationIngredient[]
  steps: MigrationStep[]
}

export interface MigrationMemory {
  recipeSlug: string
  updatedAt: string
  timesCooked: number
  timesReplaced: number
  timesSkipped: number
  lastCookedAt: string | null
  lastSelectedAt: string | null
  lovedCount: number
  okayCount: number
  latestRating: string
  neverAgain: boolean
  timeConcernCount: number
  difficultyConcernCount: number
  portionConcernCount: number
  missingIngredientCount: number
  tooManyIngredientCount: number
  wouldMakeAgainCount: number
  isFavorite: boolean
  discoveryStatus: string
  confidence: string
}

export interface MigrationPreferences {
  updatedAt: string
  householdSize: number
  eveningsPerWeek: number
  maxCookMinutes: number
  dislikedIngredientIds: string[]
  discoveryLevel: string
  repeatPreference: string
  difficultyPreference: string
  weekdayStyle: string
  dismissedPatternIds: string[]
  hasCompletedOnboarding: boolean
}

export interface MigrationFavorite {
  recipeSlug: string
  createdAt: string
}

export interface MigrationHistory {
  id: string
  recipeSlug: string
  eventType: string
  planWeekId: string | null
  plannedMealId: string | null
  replacementReason: string
  createdAt: string
}

export interface MigrationFeedback {
  id: string
  recipeSlug: string
  rating: string
  cooked: boolean
  reasons: string[]
  createdAt: string
}

export interface PersonalBundle {
  preferences: MigrationPreferences | null
  recipes: MigrationRecipe[]
  memories: MigrationMemory[]
  favorites: MigrationFavorite[]
  history: MigrationHistory[]
  feedback: MigrationFeedback[]
}

export function emptyBundle(): PersonalBundle {
  return { preferences: null, recipes: [], memories: [], favorites: [], history: [], feedback: [] }
}

export function mergeBundle(existing: PersonalBundle, incoming: PersonalBundle): PersonalBundle {
  return {
    preferences: mergePreferences(existing.preferences, incoming.preferences),
    recipes: mergeRecipes(existing.recipes, incoming.recipes),
    memories: mergeMemories(existing.memories, incoming.memories),
    favorites: mergeFavorites(existing.favorites, incoming.favorites),
    history: mergeById(existing.history, incoming.history),
    feedback: mergeById(existing.feedback, incoming.feedback),
  }
}

export function mergeRecipes(existing: MigrationRecipe[], incoming: MigrationRecipe[]): MigrationRecipe[] {
  const bySlug = new Map(existing.map((recipe) => [recipe.slug, recipe]))
  for (const recipe of incoming) {
    if (recipe.origin === 'builtIn' || recipe.origin.trim() === '') continue
    const prior = bySlug.get(recipe.slug)
    bySlug.set(recipe.slug, prior ? mergeRecipe(prior, recipe) : recipe)
  }
  return [...bySlug.values()].sort((left, right) => left.slug.localeCompare(right.slug))
}

export function mergeRecipe(server: MigrationRecipe, incoming: MigrationRecipe): MigrationRecipe {
  const incomingWins = time(incoming.updatedAt) > time(server.updatedAt)
  const next: MigrationRecipe = {
    ...server,
    id: server.id,
    slug: server.slug,
    updatedAt: incomingWins ? incoming.updatedAt : server.updatedAt,
    nameTr: textField(server.nameTr, incoming.nameTr, incomingWins),
    nameEn: textField(server.nameEn, incoming.nameEn, incomingWins),
    summaryTr: textField(server.summaryTr, incoming.summaryTr, incomingWins),
    origin: textField(server.origin, incoming.origin, incomingWins),
    collectionState: textField(server.collectionState, incoming.collectionState, incomingWins),
    sourceUrl: textField(server.sourceUrl, incoming.sourceUrl, incomingWins),
    sourceKey: textField(server.sourceKey, incoming.sourceKey, incomingWins),
    sourcePlatform: textField(server.sourcePlatform, incoming.sourcePlatform, incomingWins),
    sourceTitle: textField(server.sourceTitle, incoming.sourceTitle, incomingWins),
    userNotes: textField(server.userNotes, incoming.userNotes, incomingWins),
    baseServings: numberField(server.baseServings, incoming.baseServings, incomingWins),
    prepMinutes: numberField(server.prepMinutes, incoming.prepMinutes, incomingWins),
    cookMinutes: numberField(server.cookMinutes, incoming.cookMinutes, incomingWins),
    totalMinutes: numberField(server.totalMinutes, incoming.totalMinutes, incomingWins),
    timeIsUnknown: incomingWins ? incoming.timeIsUnknown : server.timeIsUnknown,
    servingsUnspecified: incomingWins ? incoming.servingsUnspecified : server.servingsUnspecified,
    difficulty: textField(server.difficulty, incoming.difficulty, incomingWins),
    category: textField(server.category, incoming.category, incomingWins),
    country: textField(server.country, incoming.country, incomingWins),
    diets: listField(server.diets, incoming.diets, incomingWins),
    tags: listField(server.tags, incoming.tags, incomingWins),
    photoUrl: textField(server.photoUrl, incoming.photoUrl, incomingWins),
    ingredients: groupField(server.ingredients, incoming.ingredients, incomingWins),
    steps: groupField(server.steps, incoming.steps, incomingWins),
  }
  return next
}

export function mergeMemories(existing: MigrationMemory[], incoming: MigrationMemory[]): MigrationMemory[] {
  const bySlug = new Map(existing.map((row) => [row.recipeSlug, row]))
  for (const row of incoming) {
    const prior = bySlug.get(row.recipeSlug)
    bySlug.set(row.recipeSlug, prior ? mergeMemory(prior, row) : row)
  }
  return [...bySlug.values()].sort((left, right) => left.recipeSlug.localeCompare(right.recipeSlug))
}

export function mergeMemory(server: MigrationMemory, incoming: MigrationMemory): MigrationMemory {
  const incomingWins = time(incoming.updatedAt) >= time(server.updatedAt)
  return {
    recipeSlug: server.recipeSlug,
    updatedAt: incomingWins ? incoming.updatedAt : server.updatedAt,
    timesCooked: Math.max(server.timesCooked, incoming.timesCooked),
    timesReplaced: Math.max(server.timesReplaced, incoming.timesReplaced),
    timesSkipped: Math.max(server.timesSkipped, incoming.timesSkipped),
    lastCookedAt: laterDate(server.lastCookedAt, incoming.lastCookedAt),
    lastSelectedAt: laterDate(server.lastSelectedAt, incoming.lastSelectedAt),
    lovedCount: Math.max(server.lovedCount, incoming.lovedCount),
    okayCount: Math.max(server.okayCount, incoming.okayCount),
    latestRating: textField(server.latestRating, incoming.latestRating, incomingWins),
    neverAgain: server.neverAgain || incoming.neverAgain,
    timeConcernCount: Math.max(server.timeConcernCount, incoming.timeConcernCount),
    difficultyConcernCount: Math.max(server.difficultyConcernCount, incoming.difficultyConcernCount),
    portionConcernCount: Math.max(server.portionConcernCount, incoming.portionConcernCount),
    missingIngredientCount: Math.max(server.missingIngredientCount, incoming.missingIngredientCount),
    tooManyIngredientCount: Math.max(server.tooManyIngredientCount, incoming.tooManyIngredientCount),
    wouldMakeAgainCount: Math.max(server.wouldMakeAgainCount, incoming.wouldMakeAgainCount),
    isFavorite: server.isFavorite || incoming.isFavorite,
    discoveryStatus: textField(server.discoveryStatus, incoming.discoveryStatus, incomingWins),
    confidence: textField(server.confidence, incoming.confidence, incomingWins),
  }
}

export function mergePreferences(
  server: MigrationPreferences | null,
  incoming: MigrationPreferences | null,
): MigrationPreferences | null {
  if (!incoming) return server
  if (!server) return incoming
  const incomingWins = time(incoming.updatedAt) > time(server.updatedAt)
  const chosen = incomingWins ? incoming : server
  const other = incomingWins ? server : incoming
  return {
    ...chosen,
    dislikedIngredientIds: union(server.dislikedIngredientIds, incoming.dislikedIngredientIds),
    dismissedPatternIds: union(server.dismissedPatternIds, incoming.dismissedPatternIds),
    updatedAt: time(incoming.updatedAt) >= time(server.updatedAt) ? incoming.updatedAt : server.updatedAt,
    householdSize: chosen.householdSize || other.householdSize,
  }
}

export function mergeFavorites(existing: MigrationFavorite[], incoming: MigrationFavorite[]): MigrationFavorite[] {
  const bySlug = new Map(existing.map((row) => [row.recipeSlug, row]))
  for (const row of incoming) {
    if (!bySlug.has(row.recipeSlug)) bySlug.set(row.recipeSlug, row)
  }
  return [...bySlug.values()].sort((left, right) => left.recipeSlug.localeCompare(right.recipeSlug))
}

function mergeById<T extends { id: string }>(existing: T[], incoming: T[]): T[] {
  const byId = new Map(existing.map((row) => [row.id, row]))
  for (const row of incoming) {
    if (!byId.has(row.id)) byId.set(row.id, row)
  }
  return [...byId.values()]
}

function textField(server: string, incoming: string, incomingWins: boolean): string {
  const serverFilled = server.trim() !== ''
  const incomingFilled = incoming.trim() !== ''
  if (incomingWins) return incomingFilled || !serverFilled ? incoming : server
  return serverFilled || !incomingFilled ? server : incoming
}

function numberField(server: number, incoming: number, incomingWins: boolean): number {
  if (incomingWins) return incoming !== 0 || server === 0 ? incoming : server
  return server !== 0 || incoming === 0 ? server : incoming
}

function listField(server: string[], incoming: string[], incomingWins: boolean): string[] {
  if (incomingWins) return incoming.length > 0 || server.length === 0 ? incoming : server
  return server.length > 0 || incoming.length === 0 ? server : incoming
}

function groupField<T>(server: T[], incoming: T[], incomingWins: boolean): T[] {
  if (incomingWins) return incoming.length > 0 || server.length === 0 ? incoming : server
  return server.length > 0 || incoming.length === 0 ? server : incoming
}

function union(left: string[], right: string[]): string[] {
  return [...new Set([...left, ...right])].sort((a, b) => a.localeCompare(b))
}

function laterDate(left: string | null, right: string | null): string | null {
  if (!left) return right
  if (!right) return left
  return time(right) > time(left) ? right : left
}

function time(value: string): number {
  const parsed = Date.parse(value)
  return Number.isNaN(parsed) ? 0 : parsed
}
