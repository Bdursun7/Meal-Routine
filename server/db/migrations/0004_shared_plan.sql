-- Household-owned data. The server is authoritative for these rows.
-- revision is the entity version used when two devices edit the same row.

CREATE TABLE IF NOT EXISTS household_preferences (
  household_id UUID PRIMARY KEY REFERENCES households (id) ON DELETE CASCADE,
  cooking_days INT[] NOT NULL DEFAULT '{}',
  max_weekday_minutes INT NOT NULL DEFAULT 60,
  preferred_categories TEXT[] NOT NULL DEFAULT '{}',
  preferred_proteins TEXT[] NOT NULL DEFAULT '{}',
  avoided_ingredients TEXT[] NOT NULL DEFAULT '{}',
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shared_plans (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'needsDecisions', 'ready', 'inProgress', 'completed')),
  is_finalized BOOLEAN NOT NULL DEFAULT FALSE,
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (household_id, week_start)
);

CREATE TABLE IF NOT EXISTS shared_meals (
  id UUID PRIMARY KEY,
  plan_id UUID NOT NULL REFERENCES shared_plans (id) ON DELETE CASCADE,
  day_offset INT NOT NULL,
  recipe_slug TEXT NOT NULL,
  title TEXT NOT NULL,
  recipe_owner_account_id UUID REFERENCES accounts (id),
  status TEXT NOT NULL CHECK (status IN ('proposed', 'accepted', 'vetoed', 'replaced', 'cooked')),
  revision INT NOT NULL DEFAULT 1,
  cooked_at TIMESTAMPTZ,
  replaced_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS shared_meals_plan_id_idx
  ON shared_meals (plan_id);

CREATE TABLE IF NOT EXISTS meal_reactions (
  id UUID PRIMARY KEY,
  shared_meal_id UUID NOT NULL REFERENCES shared_meals (id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts (id),
  reaction TEXT NOT NULL CHECK (reaction IN ('want', 'okay', 'veto')),
  revision INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shared_meal_id, account_id)
);

CREATE TABLE IF NOT EXISTS shared_grocery_items (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  item_key TEXT NOT NULL,
  is_checked BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by UUID REFERENCES accounts (id),
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (household_id, item_key)
);

CREATE TABLE IF NOT EXISTS household_activity (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  actor_account_id UUID REFERENCES accounts (id),
  actor_name TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL,
  meal_title TEXT NOT NULL DEFAULT '',
  detail TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS household_activity_household_id_idx
  ON household_activity (household_id, created_at DESC);

CREATE TABLE IF NOT EXISTS household_memory_signals (
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,
  together_cooked INT NOT NULL DEFAULT 0,
  both_liked INT NOT NULL DEFAULT 0,
  split_reaction INT NOT NULL DEFAULT 0,
  veto_count INT NOT NULL DEFAULT 0,
  selected_count INT NOT NULL DEFAULT 0,
  replaced_count INT NOT NULL DEFAULT 0,
  skipped_count INT NOT NULL DEFAULT 0,
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (household_id, recipe_slug)
);

-- A personal recipe shown on the shared plan. Ownership stays owner_account_id.
CREATE TABLE IF NOT EXISTS household_recipe_projections (
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  owner_account_id UUID NOT NULL REFERENCES accounts (id),
  title TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (household_id, slug)
);
