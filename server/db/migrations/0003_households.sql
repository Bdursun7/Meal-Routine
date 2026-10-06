-- Households. The product limit is 2 active members, enforced here.
-- One person belongs to at most one active household.

CREATE TABLE IF NOT EXISTS households (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL CHECK (char_length(btrim(name)) > 0),
  owner_account_id UUID NOT NULL REFERENCES accounts (id),
  revision INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS household_members (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts (id),
  role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
  display_name TEXT NOT NULL DEFAULT '',
  revision INT NOT NULL DEFAULT 1,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at TIMESTAMPTZ,
  UNIQUE (household_id, account_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS household_members_one_active_household
  ON household_members (account_id)
  WHERE left_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS household_members_one_owner
  ON household_members (household_id)
  WHERE role = 'owner' AND left_at IS NULL;

CREATE INDEX IF NOT EXISTS household_members_household_id_idx
  ON household_members (household_id);

CREATE OR REPLACE FUNCTION enforce_household_member_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  active_count integer;
BEGIN
  IF NEW.left_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT COUNT(*) INTO active_count
    FROM household_members
   WHERE household_id = NEW.household_id
     AND left_at IS NULL
     AND id <> NEW.id;
  IF active_count >= 2 THEN
    RAISE EXCEPTION 'household member limit is 2'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS household_member_limit ON household_members;
CREATE TRIGGER household_member_limit
  BEFORE INSERT OR UPDATE ON household_members
  FOR EACH ROW
  EXECUTE FUNCTION enforce_household_member_limit();

-- Spec statuses: pending, accepted, rejected, cancelled, expired.
-- The V4 client still says "revoked"; Phase 2 maps that to cancelled.
CREATE TABLE IF NOT EXISTS invites (
  id UUID PRIMARY KEY,
  household_id UUID NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES accounts (id),
  code TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  used_by UUID REFERENCES accounts (id),
  revision INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS invites_household_id_idx
  ON invites (household_id);

CREATE INDEX IF NOT EXISTS invites_status_idx
  ON invites (status);
