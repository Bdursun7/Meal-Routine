-- V5.1 pantry locations. User decision 2026-10-11 (option A).
-- The same ingredient and unit bucket may sit in more than one location.
-- 0012's pantry_items_one_row_per_bucket is replaced, not the table.
-- Existing rows already have one location, so this does not rewrite or delete any row.
-- 0001-0014 are unchanged.

ALTER TABLE pantry_items DROP CONSTRAINT IF EXISTS pantry_items_one_row_per_bucket;

ALTER TABLE pantry_items
  ADD CONSTRAINT pantry_items_one_row_per_place
  UNIQUE (household_id, ingredient_id, unit_bucket, location);
