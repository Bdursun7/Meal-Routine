-- V5.1. Opt-in flag for adding the shortfall to the grocery list when a
-- pantry row first goes from above its minimum to at or under it.
-- Default false: the threshold alone does not create a market row.
-- 0001-0012 are unchanged. No household timezone column (deferred to V7).

ALTER TABLE pantry_items
  ADD COLUMN IF NOT EXISTS auto_add_to_grocery BOOLEAN NOT NULL DEFAULT false;
