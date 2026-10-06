-- MealRoutine schema version 1. Safe to re-run: objects use IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Single row. api_version is the HTTP prefix the server speaks.
CREATE TABLE IF NOT EXISTS schema_meta (
  id INT PRIMARY KEY CHECK (id = 1),
  schema_version INT NOT NULL,
  api_version TEXT NOT NULL,
  min_client_api_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_meta (id, schema_version, api_version, min_client_api_version)
VALUES (1, 1, 'v1', 'v1')
ON CONFLICT (id) DO NOTHING;
