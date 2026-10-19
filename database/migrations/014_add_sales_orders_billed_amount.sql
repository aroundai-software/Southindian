-- Safe to run even if 013 was already applied.
ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS billed_amount numeric(14, 2) NOT NULL DEFAULT 0;
