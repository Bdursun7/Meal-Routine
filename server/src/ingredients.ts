import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * A dictionary ingredient. `id` is the identity; `names` and `aliases` are locale-keyed display data
 * (`{"tr-TR": "Domates"}`). `displayName` and `synonyms` mirror the source locale for the legacy
 * `ingredients.display_name` / `synonyms` columns and for pre-V5.1 clients.
 */
export interface Ingredient {
  id: string
  householdId: string | null
  displayName: string
  synonyms: string[]
  sourceIds: string[]
  names: Record<string, string>
  aliases: Record<string, string[]>
}

/** The locale the dictionary was authored in, and the locale V3 `import:` ids were minted from. */
export const DICTIONARY_SOURCE_LOCALE = 'tr-TR'

export interface IngredientIndex {
  byId: Map<string, Ingredient>
  bySourceId: Map<string, string>
  /** Folded source-locale name or alias -> id. Keys owned by two entries are left out. */
  byName: Map<string, string>
}

export const CUSTOM_INGREDIENT_PATTERN = /^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** Same folding the iOS dictionary uses: Turkish letters to ASCII, only [a-z0-9] kept. */
export function foldIngredientName(raw: string): string {
  const text = raw.trim().replaceAll('İ', 'i').toLowerCase().normalize('NFD').replace(/\p{M}/gu, '').replaceAll('ı', 'i')
  return text.replace(/[^a-z0-9]/g, '')
}

/** Display name in `locale`, falling back to the source locale, then to the legacy column. */
export function ingredientName(entry: Ingredient, locale: string): string {
  return entry.names[locale] ?? entry.names[DICTIONARY_SOURCE_LOCALE] ?? entry.displayName
}

/** Aliases in `locale`. Falls back to the source locale only when the entry has no row for `locale`. */
export function ingredientAliases(entry: Ingredient, locale: string): string[] {
  return entry.aliases[locale] ?? (entry.names[locale] === undefined ? entry.aliases[DICTIONARY_SOURCE_LOCALE] ?? entry.synonyms : [])
}

export function makeIngredient(input: {
  id: string
  householdId: string | null
  names: Record<string, string>
  aliases?: Record<string, string[]>
  sourceIds?: string[]
}): Ingredient {
  const aliases = input.aliases ?? {}
  const sourceName = input.names[DICTIONARY_SOURCE_LOCALE] ?? Object.values(input.names)[0] ?? input.id
  return {
    id: input.id,
    householdId: input.householdId,
    displayName: sourceName,
    synonyms: aliases[DICTIONARY_SOURCE_LOCALE] ?? [],
    sourceIds: input.sourceIds ?? [],
    names: { ...input.names },
    aliases: Object.fromEntries(Object.entries(aliases).map(([key, list]) => [key, [...list]])),
  }
}

export function cloneIngredient(row: Ingredient): Ingredient {
  return makeIngredient({ id: row.id, householdId: row.householdId, names: row.names, aliases: row.aliases, sourceIds: row.sourceIds })
}

export function buildIngredientIndex(entries: Ingredient[]): IngredientIndex {
  const byId = new Map<string, Ingredient>()
  const bySourceId = new Map<string, string>()
  const owners = new Map<string, Set<string>>()
  for (const entry of entries) {
    byId.set(entry.id, entry)
    if (entry.householdId !== null) continue
    for (const source of entry.sourceIds) bySourceId.set(source, entry.id)
    const sourceNames = [ingredientName(entry, DICTIONARY_SOURCE_LOCALE), ...(entry.aliases[DICTIONARY_SOURCE_LOCALE] ?? entry.synonyms)]
    for (const name of sourceNames) {
      const key = foldIngredientName(name)
      if (!key) continue
      const set = owners.get(key) ?? new Set<string>()
      set.add(entry.id)
      owners.set(key, set)
    }
  }
  const byName = new Map<string, string>()
  for (const [key, ids] of owners) {
    if (ids.size === 1) byName.set(key, [...ids][0]!)
  }
  return { byId, bySourceId, byName }
}

/**
 * Maps a recipe, grocery or pantry ingredient id to its dictionary id.
 * Accepted: a dictionary id, a catalog id the dictionary lists in `sourceIds`, or a V3
 * `import:<folded name>` id whose name is an unambiguous source-locale name or alias.
 * Anything else, including `manual:` grocery rows and free text, resolves to null.
 * The active UI locale never changes this result.
 */
export function resolveIngredientId(index: IngredientIndex, raw: string): string | null {
  const id = raw.trim()
  if (!id) return null
  if (index.byId.has(id)) return id
  const source = index.bySourceId.get(id)
  if (source) return source
  if (id.startsWith('import:')) return index.byName.get(foldIngredientName(id.slice('import:'.length))) ?? null
  return null
}

/** Picker suggestions for the controlled add flow, matched in `locale`. Never used to decide identity. */
export function searchIngredients(entries: Ingredient[], query: string, limit: number, locale: string = DICTIONARY_SOURCE_LOCALE): Ingredient[] {
  const needle = foldIngredientName(query)
  if (!needle) return entries.slice(0, limit)
  const ranked: { entry: Ingredient; rank: number; name: string }[] = []
  for (const entry of entries) {
    const name = ingredientName(entry, locale)
    const keys = [name, ...ingredientAliases(entry, locale)].map(foldIngredientName)
    let rank = Infinity
    for (const key of keys) {
      if (key === needle) rank = Math.min(rank, 0)
      else if (key.startsWith(needle)) rank = Math.min(rank, 1)
      else if (key.includes(needle)) rank = Math.min(rank, 2)
    }
    if (rank !== Infinity) ranked.push({ entry, rank, name })
  }
  ranked.sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name, locale) || a.entry.id.localeCompare(b.entry.id))
  return ranked.slice(0, limit).map((row) => row.entry)
}

/** Wire shape shared by `GET /v1/ingredients` and the custom-ingredient endpoint. */
export function publicIngredient(entry: Ingredient, locale: string) {
  return {
    id: entry.id,
    names: { ...entry.names },
    aliases: Object.fromEntries(Object.entries(entry.aliases).map(([key, list]) => [key, [...list]])),
    sourceIds: [...entry.sourceIds],
    displayName: ingredientName(entry, locale),
    synonyms: ingredientAliases(entry, locale),
    scope: entry.householdId ? 'household' : 'dictionary',
  }
}

interface SeedFile {
  version: number
  sourceLocale: string
  ingredients: { id: string; names: Record<string, string>; aliases: Record<string, string[]>; sourceIds: string[] }[]
}

let seedCache: Ingredient[] | null = null

/** The dictionary seed (`db/ingredients.v2.json`). Used by the in-memory store and by tests. */
export function seedIngredients(): Ingredient[] {
  if (!seedCache) {
    const file = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../db/ingredients.v2.json')
    const parsed = JSON.parse(readFileSync(file, 'utf8')) as SeedFile
    seedCache = parsed.ingredients.map((row) =>
      makeIngredient({ id: row.id, householdId: null, names: row.names, aliases: row.aliases, sourceIds: row.sourceIds }),
    )
  }
  return seedCache.map(cloneIngredient)
}
