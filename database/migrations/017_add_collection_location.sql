-- Add GPS location captured when a salesman saves a collection.
-- Run this in the Supabase SQL Editor after 016_create_payment_collections.sql.

ALTER TABLE payment_collections
  ADD COLUMN IF NOT EXISTS latitude double precision;

ALTER TABLE payment_collections
  ADD COLUMN IF NOT EXISTS longitude double precision;

ALTER TABLE payment_collections
  ADD COLUMN IF NOT EXISTS location_address text;

COMMENT ON COLUMN payment_collections.location_address IS
  'Reverse-geocoded address at the time the collection was saved.';
