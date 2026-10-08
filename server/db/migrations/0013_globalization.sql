-- V5.1 Globalization readiness. 0001-0012 are unchanged.
--
-- 1. Regional context. Accounts get locale, country, currency, measurement system and timezone;
--    households get country, currency, measurement system and timezone. They are independent codes.
--    Existing rows receive the deterministic first-deployment values (tr-TR / TR / TRY / metric).
--    No account or household stored a timezone before this migration, so the timezone backfill
--    is Europe/Istanbul. The column defaults exist only for this backfill and are dropped at the
--    end: the schema does not assume Turkey, and the server writes every value explicitly.
--    Value lists (supported locales, ISO 3166-1, ISO 4217, IANA zones) are validated by the server;
--    the CHECKs below only guard the code shape.
--
-- 2. Locale-keyed ingredient names and aliases. `ingredients.display_name` / `synonyms` stay as the
--    source-locale (tr-TR) copy; every existing value is copied into the new tables as tr-TR.
--
-- 3. Pantry units. oz and lb join g/kg in the `mass` bucket (exact definitions); cup, package, can
--    and bottle are their own buckets. Existing rows keep their bucket.
--
-- 4. Shared plan week identity. V5.0 clients sent local Monday 00:00 through a UTC date formatter,
--    so households east of UTC (every Europe/Istanbul household) stored the preceding Sunday.
--    A Sunday week_start can only come from that path; it moves to the Monday it stands for,
--    unless that household already has a plan on that Monday. The plan revision is left alone:
--    clients never read week_start back, and a bump would turn their next edit into a conflict.
--
-- 5. Household activity gets a language-independent `detail_code`. `detail` keeps the Turkish text
--    for pre-V5.1 clients; existing rows get their code from the fixed V5.0 texts.

-- 1. Regional context -------------------------------------------------------------------------

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'tr-TR',
  ADD COLUMN IF NOT EXISTS country_code TEXT NOT NULL DEFAULT 'TR',
  ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'TRY',
  ADD COLUMN IF NOT EXISTS measurement_system TEXT NOT NULL DEFAULT 'metric',
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul';

ALTER TABLE households
  ADD COLUMN IF NOT EXISTS country_code TEXT NOT NULL DEFAULT 'TR',
  ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'TRY',
  ADD COLUMN IF NOT EXISTS measurement_system TEXT NOT NULL DEFAULT 'metric',
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'accounts_regional_codes') THEN
    ALTER TABLE accounts ADD CONSTRAINT accounts_regional_codes CHECK (
      locale ~ '^[a-z]{2,3}-[A-Z]{2}$'
      AND country_code ~ '^[A-Z]{2}$'
      AND currency_code ~ '^[A-Z]{3}$'
      AND measurement_system IN ('metric', 'imperial')
      AND char_length(timezone) BETWEEN 1 AND 64
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'households_regional_codes') THEN
    ALTER TABLE households ADD CONSTRAINT households_regional_codes CHECK (
      country_code ~ '^[A-Z]{2}$'
      AND currency_code ~ '^[A-Z]{3}$'
      AND measurement_system IN ('metric', 'imperial')
      AND char_length(timezone) BETWEEN 1 AND 64
    );
  END IF;
END;
$$;

ALTER TABLE accounts
  ALTER COLUMN locale DROP DEFAULT,
  ALTER COLUMN country_code DROP DEFAULT,
  ALTER COLUMN currency_code DROP DEFAULT,
  ALTER COLUMN measurement_system DROP DEFAULT,
  ALTER COLUMN timezone DROP DEFAULT;

ALTER TABLE households
  ALTER COLUMN country_code DROP DEFAULT,
  ALTER COLUMN currency_code DROP DEFAULT,
  ALTER COLUMN measurement_system DROP DEFAULT,
  ALTER COLUMN timezone DROP DEFAULT;

-- 2. Locale-keyed ingredient names and aliases -----------------------------------------------

CREATE TABLE IF NOT EXISTS ingredient_names (
  ingredient_id TEXT NOT NULL REFERENCES ingredients (id) ON DELETE CASCADE,
  locale TEXT NOT NULL CHECK (locale ~ '^[a-z]{2,3}-[A-Z]{2}$'),
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 160),
  PRIMARY KEY (ingredient_id, locale)
);

CREATE TABLE IF NOT EXISTS ingredient_aliases (
  ingredient_id TEXT NOT NULL REFERENCES ingredients (id) ON DELETE CASCADE,
  locale TEXT NOT NULL CHECK (locale ~ '^[a-z]{2,3}-[A-Z]{2}$'),
  alias TEXT NOT NULL CHECK (char_length(alias) BETWEEN 1 AND 160),
  position INT NOT NULL CHECK (position >= 1),
  PRIMARY KEY (ingredient_id, locale, alias)
);

CREATE INDEX IF NOT EXISTS ingredient_aliases_lookup_idx
  ON ingredient_aliases (locale, alias);

INSERT INTO ingredient_names (ingredient_id, locale, display_name)
SELECT id, 'tr-TR', display_name FROM ingredients
ON CONFLICT (ingredient_id, locale) DO NOTHING;

INSERT INTO ingredient_aliases (ingredient_id, locale, alias, position)
SELECT i.id, 'tr-TR', s.alias, s.position::int
  FROM ingredients i
  CROSS JOIN LATERAL unnest(i.synonyms) WITH ORDINALITY AS s (alias, position)
 WHERE char_length(s.alias) BETWEEN 1 AND 160
ON CONFLICT (ingredient_id, locale, alias) DO NOTHING;

-- 3. Pantry units ----------------------------------------------------------------------------

ALTER TABLE pantry_items DROP CONSTRAINT IF EXISTS pantry_items_unit_check;
ALTER TABLE pantry_items DROP CONSTRAINT IF EXISTS pantry_items_unit_code;
ALTER TABLE pantry_items ADD CONSTRAINT pantry_items_unit_code CHECK (unit IN (
  'g', 'kg', 'oz', 'lb', 'ml', 'l', 'piece', 'tsp', 'tbsp', 'cup', 'package', 'can', 'bottle',
  'clove', 'pinch', 'slice', 'sprig', 'toTaste'
));

ALTER TABLE pantry_items DROP CONSTRAINT IF EXISTS pantry_items_one_row_per_bucket;
ALTER TABLE pantry_items DROP COLUMN IF EXISTS unit_bucket;
ALTER TABLE pantry_items ADD COLUMN unit_bucket TEXT GENERATED ALWAYS AS (
  CASE WHEN unit IN ('g', 'kg', 'oz', 'lb') THEN 'mass' WHEN unit IN ('ml', 'l') THEN 'volume' ELSE unit END
) STORED;
ALTER TABLE pantry_items ADD CONSTRAINT pantry_items_one_row_per_bucket UNIQUE (household_id, ingredient_id, unit_bucket);

-- 4. Shared plan week identity -----------------------------------------------------------------

UPDATE shared_plans p
   SET week_start = p.week_start + 1
 WHERE EXTRACT(ISODOW FROM p.week_start) = 7
   AND NOT EXISTS (
     SELECT 1 FROM shared_plans q
      WHERE q.household_id = p.household_id
        AND q.week_start = p.week_start + 1
   );

-- 5. Household activity detail codes -----------------------------------------------------------

ALTER TABLE household_activity ADD COLUMN IF NOT EXISTS detail_code TEXT;

UPDATE household_activity
   SET detail_code = CASE detail
     WHEN 'Ortak plan kuruldu' THEN 'planCreated'
     WHEN 'İşaretlendi' THEN 'checked'
     WHEN 'İşaret kalktı' THEN 'unchecked'
     WHEN 'Pişti' THEN 'cooked'
     WHEN 'Yemek değişti' THEN 'replaced'
     WHEN 'Bu hafta olmaz' THEN 'vetoed'
     WHEN 'Tepki güncellendi' THEN 'reactionUpdated'
   END
 WHERE detail_code IS NULL;
