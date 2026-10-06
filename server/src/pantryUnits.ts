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
  aliases: string[]
}

const specs: Spec[] = [
  { code: 'g', family: 'mass', basePerUnit: 1, aliases: ['g', 'gr', 'gm', 'gram', 'grams', 'gramme', 'grammes'] },
  { code: 'kg', family: 'mass', basePerUnit: 1000, aliases: ['kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms', 'kilogramme', 'kilogrammes'] },
  { code: 'ml', family: 'volume', basePerUnit: 1, aliases: ['ml', 'mls', 'milliliter', 'milliliters', 'millilitre', 'millilitres', 'mililitre', 'mililitres'] },
  { code: 'l', family: 'volume', basePerUnit: 1000, aliases: ['l', 'lt', 'ltr', 'liter', 'liters', 'litre', 'litres'] },
  { code: 'piece', family: null, basePerUnit: 1, aliases: ['piece', 'pieces', 'pc', 'pcs', 'adet'] },
  { code: 'tbsp', family: null, basePerUnit: 1, aliases: ['tbsp', 'tablespoon', 'tablespoons', 'yemek kaşığı', 'yemek kasigi', 'yk'] },
  { code: 'tsp', family: null, basePerUnit: 1, aliases: ['tsp', 'teaspoon', 'teaspoons', 'tatlı kaşığı', 'tatli kasigi', 'tk'] },
  { code: 'clove', family: null, basePerUnit: 1, aliases: ['clove', 'cloves', 'diş', 'dis'] },
  { code: 'pinch', family: null, basePerUnit: 1, aliases: ['pinch', 'pinches', 'tutam'] },
  { code: 'slice', family: null, basePerUnit: 1, aliases: ['slice', 'slices', 'dilim'] },
  { code: 'sprig', family: null, basePerUnit: 1, aliases: ['sprig', 'sprigs', 'dal'] },
  { code: 'toTaste', family: null, basePerUnit: 1, aliases: ['toTaste', 'to taste', 'to-taste', 'damak tadına', 'damak tadina'] },
]

const byAlias = new Map<string, Spec>()
for (const spec of specs) {
  for (const alias of spec.aliases) byAlias.set(foldUnit(alias), spec)
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

export function canonicalUnit(raw: string, allowUnknown: boolean): string | null {
  const parsed = parsePantryUnit(raw)
  if (!parsed.code) return null
  if (!parsed.known && !allowUnknown) return null
  return parsed.code
}
