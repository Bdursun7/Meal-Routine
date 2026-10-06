-- Delivery fields for the notification queue and a master switch.
-- 0001–0008 stay as they are. notification_batches is the outbox.

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS master_enabled BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS body TEXT NOT NULL DEFAULT '';

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS route TEXT NOT NULL DEFAULT '';

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS meal_id TEXT NOT NULL DEFAULT '';

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';

ALTER TABLE notification_batches
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;
