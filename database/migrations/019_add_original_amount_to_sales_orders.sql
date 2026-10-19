-- Migration: Add original_amount to sales_orders
-- Purpose: Track the older amount of the sales order before it was edited

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS original_amount numeric(10, 2);

COMMENT ON COLUMN public.sales_orders.original_amount IS 'The original net amount before any edits were made to this order';
