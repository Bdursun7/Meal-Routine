CREATE TABLE IF NOT EXISTS pantry_items (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  ingredient_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  quantity NUMERIC(12,3) NOT NULL CHECK (quantity >= 0),
  unit TEXT NOT NULL,
  location TEXT NOT NULL CHECK (location IN ('pantry', 'refrigerator', 'freezer', 'other')),
  minimum_quantity NUMERIC(12,3),
  best_before DATE,
  revision INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (household_id, ingredient_id, unit),
  CHECK (minimum_quantity IS NULL OR minimum_quantity >= 0)
);

CREATE INDEX IF NOT EXISTS pantry_items_household_idx
  ON pantry_items (household_id, updated_at);

CREATE TABLE IF NOT EXISTS pantry_idempotency (
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  response_body JSONB NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (account_id, idempotency_key)
);
