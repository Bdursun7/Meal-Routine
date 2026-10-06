-- Idempotency, conflict versions, the sync queue, push tokens, and API version.

CREATE TABLE IF NOT EXISTS idempotency_keys (
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  response_status INT,
  response_body JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (account_id, idempotency_key)
);

-- One revision per entity the server has accepted. entity_id is text because
-- some keys are recipe slugs rather than UUIDs.
CREATE TABLE IF NOT EXISTS entity_versions (
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  account_id UUID REFERENCES accounts (id) ON DELETE CASCADE,
  household_id UUID REFERENCES households (id) ON DELETE CASCADE,
  revision INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS sync_operations (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  household_id UUID REFERENCES households (id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL CHECK (status IN ('pending', 'syncing', 'completed', 'failed', 'requiresResolution')),
  retry_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sync_operations_account_status_idx
  ON sync_operations (account_id, status);

-- token is the APNs device token. Do not log this column.
CREATE TABLE IF NOT EXISTS device_push_tokens (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  disabled_at TIMESTAMPTZ,
  UNIQUE (account_id, token_hash)
);

CREATE TABLE IF NOT EXISTS notification_preferences (
  account_id UUID PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
  invites_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  weekly_plan_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  meal_veto_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  meal_replacement_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  plan_finalized_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Groups bursts of the same notification so the phone is not spammed.
CREATE TABLE IF NOT EXISTS notification_batches (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  event_count INT NOT NULL DEFAULT 1,
  last_event_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, kind, household_id, window_start)
);

CREATE TABLE IF NOT EXISTS api_schema_versions (
  id INT PRIMARY KEY CHECK (id = 1),
  schema_version INT NOT NULL,
  api_version TEXT NOT NULL,
  min_client_api_version TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO api_schema_versions (id, schema_version, api_version, min_client_api_version)
VALUES (1, 1, 'v1', 'v1')
ON CONFLICT (id) DO NOTHING;
