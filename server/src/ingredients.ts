import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export interface Ingredient {
  id: string
  householdId: string | null
  displayName: string
  synonyms: string[]
  sourceIds: string[]
}

export interface IngredientIndex {
  byId: Map<string, Ingredient>
  bySourceId: Map<string, string>
  /** Folded seed name or synonym -> id. Keys owned by two entries are left out. */
  byName: Map<string, string>
}

export const CUSTOM_INGREDIENT_PATTERN = /^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** Same folding the iOS dictionary uses: Turkish letters to ASCII, only [a-z0-9] kept. */
export function foldIngredientName(raw: string): string {
  const text = raw.trim().replaceAll('İ', 'i').toLowerCase().normalize('NFD').replace(/\p{M}/gu, '').replaceAll('ı', 'i')
  return text.replace(/[^a-z0-9]/g, '')
}

export function buildIngredientIndex(entries: Ingredient[]): IngredientIndex {
  const byId = new Map<string, Ingredient>()
  const bySourceId = new Map<string, string>()
  const owners = new Map<string, Set<string>>()
  for (const entry of entries) {
    byId.set(entry.id, entry)
    if (entry.householdId !== null) continue
    for (const source of entry.sourceIds) bySourceId.set(source, entry.id)
    for (const name of [entry.displayName, ...entry.synonyms]) {
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
 * `import:<folded name>` id whose name is an unambiguous seed name or synonym.
 * Anything else, including `manual:` grocery rows and free text, resolves to null.
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

/** Picker suggestions for the controlled add flow. Never used to decide identity. */
export function searchIngredients(entries: Ingredient[], query: string, limit: number): Ingredient[] {
  const needle = foldIngredientName(query)
  if (!needle) return entries.slice(0, limit)
  const ranked: { entry: Ingredient; rank: number }[] = []
  for (const entry of entries) {
    const keys = [entry.displayName, ...entry.synonyms].map(foldIngredientName)
    let rank = Infinity
    for (const key of keys) {
      if (key === needle) rank = Math.min(rank, 0)
      else if (key.startsWith(needle)) rank = Math.min(rank, 1)
      else if (key.includes(needle)) rank = Math.min(rank, 2)
    }
    if (rank !== Infinity) ranked.push({ entry, rank })
  }
  ranked.sort((a, b) => a.rank - b.rank || a.entry.displayName.localeCompare(b.entry.displayName, 'tr'))
  return ranked.slice(0, limit).map((row) => row.entry)
}

interface SeedFile {
  version: number
  ingredients: { id: string; name: string; synonyms: string[]; sourceIds: string[] }[]
}

let seedCache: Ingredient[] | null = null

/** The seed the 0012 migration inserts. Used by the in-memory store and by tests. */
export function seedIngredients(): Ingredient[] {
  if (!seedCache) {
    const file = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../db/ingredients.v1.json')
    const parsed = JSON.parse(readFileSync(file, 'utf8')) as SeedFile
    seedCache = parsed.ingredients.map((row) => ({
      id: row.id,
      householdId: null,
      displayName: row.name,
      synonyms: row.synonyms,
      sourceIds: row.sourceIds,
    }))
  }
  return seedCache.map((row) => ({ ...row, synonyms: [...row.synonyms], sourceIds: [...row.sourceIds] }))
}
