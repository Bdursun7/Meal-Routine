export type PantryUnitFamily = 'mass' | 'volume'

export interface ParsedPantryUnit {
  code: string
  family: PantryUnitFamily | null
  basePerUnit: number
  known: boolean
}

interface Spec {
  code: string
  family: PantryUnitFamily | null
  basePerUnit: number
  /** The code itself and language-neutral abbreviations. */
  aliases: string[]
  /** Typed spellings, keyed by language. Parsing accepts every language; no alias names two codes. */
  localeAliases: Record<string, string[]>
}

/**
 * Structured unit codes shared with the iOS `UnitCode` enum. Mass converts through grams with
 * exact definitions (1 oz = 28.349523125 g, 1 lb = 453.59237 g); volume through millilitres.
 * Spoons and cups are not converted: their size differs by measurement system. piece, package,
 * can and bottle never convert to mass or volume without ingredient-specific data.
 */
const specs: Spec[] = [
  { code: 'g', family: 'mass', basePerUnit: 1, aliases: ['g', 'gr', 'gm'], localeAliases: { en: ['gram', 'grams', 'gramme', 'grammes'], tr: ['gram'] } },
  { code: 'kg', family: 'mass', basePerUnit: 1000, aliases: ['kg', 'kgs'], localeAliases: { en: ['kilo', 'kilos', 'kilogram', 'kilograms', 'kilogramme', 'kilogrammes'], tr: ['kilo', 'kilogram'] } },
  { code: 'oz', family: 'mass', basePerUnit: 28.349523125, aliases: ['oz'], localeAliases: { en: ['ounce', 'ounces'], tr: ['ons'] } },
  { code: 'lb', family: 'mass', basePerUnit: 453.59237, aliases: ['lb', 'lbs'], localeAliases: { en: ['pound', 'pounds'], tr: ['libre'] } },
  { code: 'ml', family: 'volume', basePerUnit: 1, aliases: ['ml', 'mls'], localeAliases: { en: ['milliliter', 'milliliters', 'millilitre', 'millilitres'], tr: ['mililitre', 'mililitres'] } },
  { code: 'l', family: 'volume', basePerUnit: 1000, aliases: ['l', 'lt', 'ltr'], localeAliases: { en: ['liter', 'liters', 'litre', 'litres'], tr: ['litre'] } },
  { code: 'piece', family: null, basePerUnit: 1, aliases: ['piece', 'pc', 'pcs'], localeAliases: { en: ['pieces'], tr: ['adet'] } },
  { code: 'tsp', family: null, basePerUnit: 1, aliases: ['tsp'], localeAliases: { en: ['teaspoon', 'teaspoons'], tr: ['tatlı kaşığı', 'tatli kasigi', 'tk'] } },
  { code: 'tbsp', family: null, basePerUnit: 1, aliases: ['tbsp'], localeAliases: { en: ['tablespoon', 'tablespoons'], tr: ['yemek kaşığı', 'yemek kasigi', 'yk'] } },
  { code: 'cup', family: null, basePerUnit: 1, aliases: ['cup'], localeAliases: { en: ['cups'], tr: ['su bardağı', 'su bardagi', 'bardak'] } },
  { code: 'package', family: null, basePerUnit: 1, aliases: ['package', 'pkg'], localeAliases: { en: ['packages', 'pack', 'packs'], tr: ['paket'] } },
  { code: 'can', family: null, basePerUnit: 1, aliases: ['can'], localeAliases: { en: ['cans', 'tin', 'tins'], tr: ['kutu', 'konserve'] } },
  { code: 'bottle', family: null, basePerUnit: 1, aliases: ['bottle'], localeAliases: { en: ['bottles'], tr: ['şişe', 'sise'] } },
  { code: 'clove', family: null, basePerUnit: 1, aliases: ['clove'], localeAliases: { en: ['cloves'], tr: ['diş', 'dis'] } },
  { code: 'pinch', family: null, basePerUnit: 1, aliases: ['pinch'], localeAliases: { en: ['pinches'], tr: ['tutam'] } },
  { code: 'slice', family: null, basePerUnit: 1, aliases: ['slice'], localeAliases: { en: ['slices'], tr: ['dilim'] } },
  { code: 'sprig', family: null, basePerUnit: 1, aliases: ['sprig'], localeAliases: { en: ['sprigs'], tr: ['dal'] } },
  { code: 'toTaste', family: null, basePerUnit: 1, aliases: ['toTaste', 'to-taste'], localeAliases: { en: ['to taste'], tr: ['damak tadına', 'damak tadina'] } },
]

export const PANTRY_UNIT_CODES: readonly string[] = Object.freeze(specs.map((spec) => spec.code))

const byAlias = new Map<string, Spec>()
for (const spec of specs) {
  for (const alias of [...spec.aliases, ...Object.values(spec.localeAliases).flat()]) {
    const key = foldUnit(alias)
    const owner = byAlias.get(key)
    if (owner && owner.code !== spec.code) throw new Error(`unit alias ${alias} names ${owner.code} and ${spec.code}`)
    byAlias.set(key, spec)
  }
}

export function foldUnit(raw: string): string {
  let text = raw.trim().replaceAll('İ', 'i').toLowerCase()
  text = text.normalize('NFD').replace(/\p{M}/gu, '')
  let folded = ''
  for (const character of text) {
    switch (character) {
      case 'ç': folded += 'c'; break
      case 'ğ': folded += 'g'; break
      case 'ı': folded += 'i'; break
      case 'ö': folded += 'o'; break
      case 'ş': folded += 's'; break
      case 'ü': folded += 'u'; break
      default:
        if (/[a-z0-9]/.test(character)) folded += character
    }
  }
  return folded
}

export function parsePantryUnit(raw: string): ParsedPantryUnit {
  const spec = byAlias.get(foldUnit(raw))
  if (spec) return { code: spec.code, family: spec.family, basePerUnit: spec.basePerUnit, known: true }
  const code = raw.trim().replaceAll('İ', 'i').toLowerCase().split(/\s+/).join(' ')
  return { code, family: null, basePerUnit: 1, known: false }
}

export function unitsCompatible(left: string, right: string): boolean {
  const a = parsePantryUnit(left)
  const b = parsePantryUnit(right)
  if (!a.code || !b.code) return false
  if (a.family && a.family === b.family) return true
  return a.code === b.code
}

export function convertPantryQuantity(value: number, from: string, to: string): number | null {
  if (!unitsCompatible(from, to)) return null
  const source = parsePantryUnit(from)
  const target = parsePantryUnit(to)
  if (source.family && source.family === target.family) {
    return roundPantryQuantity((value * source.basePerUnit) / target.basePerUnit)
  }
  return roundPantryQuantity(value)
}

export function roundPantryQuantity(value: number): number {
  return Math.round(value * 1000) / 1000
}

/** Known unit code, or null. Pantry never stores a unit outside the shared unit table. */
export function canonicalUnit(raw: string): string | null {
  const parsed = parsePantryUnit(raw)
  if (!parsed.code || !parsed.known) return null
  return parsed.code
}
