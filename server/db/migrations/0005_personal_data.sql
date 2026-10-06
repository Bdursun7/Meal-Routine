-- Personal data uploaded from the device after sign-in (V4.1 migration).
-- These rows belong to the account, not the household.
-- Deleting an account cascades them. Household rows are not stored here.

CREATE TABLE IF NOT EXISTS personal_preferences (
  account_id UUID PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
  household_size INT NOT NULL DEFAULT 2,
  evenings_per_week INT NOT NULL DEFAULT 7,
  max_cook_minutes INT NOT NULL DEFAULT 60,
  disliked_ingredient_ids TEXT[] NOT NULL DEFAULT '{}',
  discovery_level TEXT NOT NULL DEFAULT 'balanced',
  repeat_preference TEXT NOT NULL DEFAULT 'balanced',
  difficulty_preference TEXT NOT NULL DEFAULT 'mostlyEasy',
  weekday_style TEXT NOT NULL DEFAULT 'mostlyQuick',
  dismissed_pattern_ids TEXT[] NOT NULL DEFAULT '{}',
  has_completed_onboarding BOOLEAN NOT NULL DEFAULT FALSE,
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS personal_recipes (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  name_tr TEXT NOT NULL DEFAULT '',
  name_en TEXT NOT NULL DEFAULT '',
  summary_tr TEXT NOT NULL DEFAULT '',
  origin TEXT NOT NULL DEFAULT 'userImported',
  collection_state TEXT NOT NULL DEFAULT 'draft',
  source_url TEXT NOT NULL DEFAULT '',
  source_key TEXT NOT NULL DEFAULT '',
  source_platform TEXT NOT NULL DEFAULT '',
  source_title TEXT NOT NULL DEFAULT '',
  user_notes TEXT NOT NULL DEFAULT '',
  base_servings INT NOT NULL DEFAULT 2,
  prep_minutes INT NOT NULL DEFAULT 0,
  cook_minutes INT NOT NULL DEFAULT 0,
  total_minutes INT NOT NULL DEFAULT 0,
  time_is_unknown BOOLEAN NOT NULL DEFAULT FALSE,
  servings_unspecified BOOLEAN NOT NULL DEFAULT FALSE,
  difficulty TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  country TEXT NOT NULL DEFAULT '',
  diets TEXT[] NOT NULL DEFAULT '{}',
  tags TEXT[] NOT NULL DEFAULT '{}',
  photo_url TEXT NOT NULL DEFAULT '',
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, slug)
);

CREATE UNIQUE INDEX IF NOT EXISTS personal_recipes_source_url_idx
  ON personal_recipes (account_id, source_url)
  WHERE source_url <> '';

CREATE UNIQUE INDEX IF NOT EXISTS personal_recipes_source_key_idx
  ON personal_recipes (account_id, source_key)
  WHERE source_key <> '';

CREATE TABLE IF NOT EXISTS personal_recipe_ingredients (
  id UUID PRIMARY KEY,
  recipe_id UUID NOT NULL REFERENCES personal_recipes (id) ON DELETE CASCADE,
  sort_index INT NOT NULL,
  ingredient_id TEXT NOT NULL DEFAULT '',
  name_tr TEXT NOT NULL DEFAULT '',
  name_en TEXT NOT NULL DEFAULT '',
  quantity DOUBLE PRECISION,
  unit TEXT NOT NULL DEFAULT '',
  note_tr TEXT NOT NULL DEFAULT '',
  is_optional BOOLEAN NOT NULL DEFAULT FALSE,
  include_in_grocery BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (recipe_id, sort_index)
);

CREATE TABLE IF NOT EXISTS personal_recipe_steps (
  id UUID PRIMARY KEY,
  recipe_id UUID NOT NULL REFERENCES personal_recipes (id) ON DELETE CASCADE,
  sort_index INT NOT NULL,
  text_tr TEXT NOT NULL DEFAULT '',
  text_en TEXT NOT NULL DEFAULT '',
  minutes INT,
  UNIQUE (recipe_id, sort_index)
);

CREATE TABLE IF NOT EXISTS meal_memory (
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,
  times_cooked INT NOT NULL DEFAULT 0,
  times_replaced INT NOT NULL DEFAULT 0,
  times_skipped INT NOT NULL DEFAULT 0,
  last_cooked_at TIMESTAMPTZ,
  last_selected_at TIMESTAMPTZ,
  loved_count INT NOT NULL DEFAULT 0,
  okay_count INT NOT NULL DEFAULT 0,
  latest_rating TEXT NOT NULL DEFAULT '',
  never_again BOOLEAN NOT NULL DEFAULT FALSE,
  time_concern_count INT NOT NULL DEFAULT 0,
  difficulty_concern_count INT NOT NULL DEFAULT 0,
  portion_concern_count INT NOT NULL DEFAULT 0,
  missing_ingredient_count INT NOT NULL DEFAULT 0,
  too_many_ingredient_count INT NOT NULL DEFAULT 0,
  would_make_again_count INT NOT NULL DEFAULT 0,
  is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
  discovery_status TEXT NOT NULL DEFAULT 'unknown',
  confidence TEXT NOT NULL DEFAULT 'low',
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, recipe_slug)
);

CREATE TABLE IF NOT EXISTS favorites (
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revision INT NOT NULL DEFAULT 1,
  PRIMARY KEY (account_id, recipe_slug)
);

CREATE TABLE IF NOT EXISTS cooking_history (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,
  event_type TEXT NOT NULL,
  plan_week_id UUID,
  planned_meal_id UUID,
  replacement_reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cooking_history_account_id_idx
  ON cooking_history (account_id, created_at DESC);

CREATE TABLE IF NOT EXISTS recipe_feedback (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  recipe_slug TEXT NOT NULL,
  rating TEXT NOT NULL,
  cooked BOOLEAN NOT NULL DEFAULT FALSE,
  reasons TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS recipe_feedback_account_id_idx
  ON recipe_feedback (account_id, recipe_slug);

-- Tracks the local-to-server upload (spec section 15). Not the personal rows themselves.
CREATE TABLE IF NOT EXISTS personal_migrations (
  account_id UUID PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'uploaded', 'confirmed')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at TIMESTAMPTZ
);
