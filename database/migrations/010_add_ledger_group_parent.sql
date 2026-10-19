-- Migration: Add ledger group + group parent to customers / ledgers
-- Date: 2026-09-10
-- Purpose: Store Tally ledger grouping the same way products store stock groups.
--
-- Tally example:
--   Ledger MATHA ELECT.SANITARY&HW-KAMPTEC
--     Under (category)        = KOTTAYAM-KAMP        → ledger_group
--     That group's Under      = Central Zone Kamp    → ledger_group_parent
--
-- customers.customer_category_name already stores the immediate Under.
-- These columns keep the Tally names explicit and add the missing parent.

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS ledger_group text NULL;

ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS ledger_group_parent text NULL;

COMMENT ON COLUMN public.customers.ledger_group IS
  'Tally group the ledger is under (PARENT). Example: KOTTAYAM-KAMP';

COMMENT ON COLUMN public.customers.ledger_group_parent IS
  'Parent of ledger_group from Tally (group Under). Example: Central Zone Kamp';

CREATE INDEX IF NOT EXISTS idx_customers_ledger_group
  ON public.customers (ledger_group);

CREATE INDEX IF NOT EXISTS idx_customers_ledger_group_parent
  ON public.customers (ledger_group_parent);

-- ledgers.ledger_group already exists (immediate Under). Add the parent only.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'ledgers'
  ) THEN
    ALTER TABLE public.ledgers
      ADD COLUMN IF NOT EXISTS ledger_group_parent text NULL;

    COMMENT ON COLUMN public.ledgers.ledger_group_parent IS
      'Parent of ledger_group from Tally (group Under). Example: Central Zone Kamp';

    CREATE INDEX IF NOT EXISTS idx_ledgers_ledger_group_parent
      ON public.ledgers (ledger_group_parent);
  END IF;
END $$;
