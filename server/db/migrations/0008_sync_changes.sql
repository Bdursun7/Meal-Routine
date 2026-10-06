-- Delta cursor for shared-data pull, and grocery quantity so an idempotent
-- replay cannot double an add. Does not change 0001–0007.

ALTER TABLE shared_grocery_items
  ADD COLUMN IF NOT EXISTS quantity INT NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS sync_changes (
  cursor BIGSERIAL PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  revision INT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sync_changes_household_cursor_idx
  ON sync_changes (household_id, cursor);
