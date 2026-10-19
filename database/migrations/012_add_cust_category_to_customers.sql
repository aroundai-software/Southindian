-- Migration: Add Tally custom ledger field Cust.Category
-- Date: 2026-09-14
-- Purpose: Store the Tally UDF "Cust.Category" (e.g. Malappuram).
--          This is NOT the ledger Under group (that stays in ledger_group /
--          customer_category_name).

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS cust_category text NULL;

COMMENT ON COLUMN public.customers.cust_category IS
  'Tally custom ledger field Cust.Category. Example: Malappuram';

CREATE INDEX IF NOT EXISTS idx_customers_cust_category
  ON public.customers (cust_category);
