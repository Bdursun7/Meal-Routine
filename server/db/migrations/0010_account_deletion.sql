-- Account deletion audit. The account row stays so household history can keep
-- a member id, but names, identities, sessions, and personal rows are cleared
-- by the delete route. 0001–0009 are unchanged.

CREATE TABLE IF NOT EXISTS account_deletions (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id),
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  household_outcome TEXT NOT NULL CHECK (household_outcome IN ('none', 'left', 'deleted'))
);

CREATE INDEX IF NOT EXISTS account_deletions_account_id_idx
  ON account_deletions (account_id, deleted_at DESC);
