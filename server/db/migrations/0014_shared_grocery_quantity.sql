-- V5.1 shared grocery amount. User-approved 2026-10-11.
-- Adds a decimal amount, a unit, and an optional card source.
-- 0001-0013 are unchanged. The integer quantity column stays for plan
-- lines and older clients. Unit stays null on those rows.
-- quantity_decimal is backfilled from the integer so existing rows still read.

ALTER TABLE shared_grocery_items
  ADD COLUMN IF NOT EXISTS quantity_decimal NUMERIC(12,3),
  ADD COLUMN IF NOT EXISTS unit TEXT,
  ADD COLUMN IF NOT EXISTS line_source TEXT;

UPDATE shared_grocery_items
  SET quantity_decimal = quantity
  WHERE quantity_decimal IS NULL;
