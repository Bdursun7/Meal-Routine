-- V5.1 pantry locations. User decision 2026-10-11 (option A).
-- The same ingredient and unit bucket may sit in more than one location.
-- 0012's pantry_items_one_row_per_bucket is replaced, not the table.
-- Existing rows already have one location, so this does not rewrite or delete any row.
-- 0001-0014 are unchanged.

ALTER TABLE pantry_items DROP CONSTRAINT IF EXISTS pantry_items_one_row_per_bucket;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pantry_items_one_row_per_place'
                 AND conrelid = 'pantry_items'::regclass) THEN
    ALTER TABLE pantry_items
      ADD CONSTRAINT pantry_items_one_row_per_place
      UNIQUE (household_id, ingredient_id, unit_bucket, location);
  END IF;
END $$;

-- Databases that first ran the early foundation 0012 (best_before/revision columns) are
-- repaired by src/migrate.ts before this file runs: the early table is kept as
-- pantry_items_foundation_0012 and the canonical 0012/0013 are applied. Copy its rows
-- that fit the canonical schema; anything that does not fit stays in the kept table.
DO $$
BEGIN
  IF to_regclass('pantry_items_foundation_0012') IS NOT NULL THEN
    INSERT INTO pantry_items (id, household_id, ingredient_id, display_name, quantity, unit, location,
                              minimum_quantity, date_type, date_value, version, created_at, updated_at)
    SELECT f.id, f.household_id, f.ingredient_id, f.display_name, f.quantity, f.unit, f.location,
           f.minimum_quantity,
           CASE WHEN f.best_before IS NULL THEN NULL ELSE 'bestBefore' END, f.best_before,
           GREATEST(f.revision, 1), f.created_at, f.updated_at
    FROM pantry_items_foundation_0012 f
    WHERE EXISTS (SELECT 1 FROM ingredients i WHERE i.id = f.ingredient_id
                  AND (i.household_id IS NULL OR i.household_id = f.household_id))
      AND f.unit IN ('g', 'kg', 'ml', 'l', 'piece', 'tbsp', 'tsp', 'clove', 'pinch', 'slice', 'sprig', 'toTaste')
      AND char_length(f.display_name) BETWEEN 1 AND 160
    ORDER BY f.updated_at DESC
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
