-- Product analytics and on-device diagnostic summaries.
-- Rows older than 30 days are deleted on the next ingest.
-- 0001–0010 are unchanged.

CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  properties JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS analytics_events_received_at_idx
  ON analytics_events (received_at);

CREATE INDEX IF NOT EXISTS analytics_events_account_id_idx
  ON analytics_events (account_id, received_at DESC);

CREATE TABLE IF NOT EXISTS client_diagnostics (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('crash', 'hang', 'cpu', 'disk', 'metric')),
  count INTEGER NOT NULL CHECK (count >= 0 AND count <= 1000),
  exception_type TEXT,
  signal TEXT,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS client_diagnostics_received_at_idx
  ON client_diagnostics (received_at);

CREATE INDEX IF NOT EXISTS client_diagnostics_account_id_idx
  ON client_diagnostics (account_id, received_at DESC);
