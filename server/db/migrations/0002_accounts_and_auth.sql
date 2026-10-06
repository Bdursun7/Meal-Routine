-- Accounts, sign-in identities, and refresh sessions.
-- Providers the product ships: apple, google.
-- provider 'dev' is inserted only by POST /v1/auth/dev when NODE_ENV=development.

CREATE TABLE IF NOT EXISTS accounts (
  id UUID PRIMARY KEY,
  display_name TEXT NOT NULL DEFAULT '',
  given_name TEXT NOT NULL DEFAULT '',
  family_name TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS auth_identities (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('apple', 'google', 'dev')),
  subject TEXT NOT NULL,
  email TEXT,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  is_private_relay BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, subject)
);

CREATE INDEX IF NOT EXISTS auth_identities_account_id_idx
  ON auth_identities (account_id);

-- Lookup for "this verified email already belongs to an account".
-- Private relay addresses are excluded so they never merge two people.
CREATE INDEX IF NOT EXISTS auth_identities_verified_email_idx
  ON auth_identities (lower(email))
  WHERE email IS NOT NULL
    AND email_verified
    AND is_private_relay = FALSE;

CREATE TABLE IF NOT EXISTS sessions (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  family_id UUID NOT NULL,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sessions_account_id_idx
  ON sessions (account_id);

CREATE INDEX IF NOT EXISTS sessions_family_id_idx
  ON sessions (family_id);
