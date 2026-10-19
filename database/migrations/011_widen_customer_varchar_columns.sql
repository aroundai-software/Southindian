-- Migration: Widen short customer text columns
-- Date: 2026-09-10
-- Purpose: Tally mobile / GST / pincode / city / state values often exceed varchar(15).
--          One oversize value was failing entire 100-row upsert batches, so only
--          ~3195 of 5005 ledgers were saved.

ALTER TABLE public.customers
  ALTER COLUMN mobile_number TYPE text;

ALTER TABLE public.customers
  ALTER COLUMN pincode TYPE text;

ALTER TABLE public.customers
  ALTER COLUMN gst_number TYPE text;

ALTER TABLE public.customers
  ALTER COLUMN city TYPE text;

ALTER TABLE public.customers
  ALTER COLUMN state TYPE text;
