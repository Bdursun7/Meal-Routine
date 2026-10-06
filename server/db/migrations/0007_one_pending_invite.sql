-- One active (pending) invite per household. Expired, cancelled, rejected,
-- and accepted rows stay in the table and do not block a later invite.
-- Safe to re-run. Does not change 0001–0006.

CREATE UNIQUE INDEX IF NOT EXISTS invites_one_pending
  ON invites (household_id)
  WHERE status = 'pending';
