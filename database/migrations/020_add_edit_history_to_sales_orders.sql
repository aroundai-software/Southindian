-- Migration: Add edit_history to sales_orders
-- Purpose: Track detailed change history (rate, discount, quantity, items, notes) whenever an order is edited

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS edit_history jsonb;

COMMENT ON COLUMN public.sales_orders.edit_history IS 'Detailed log of order edits containing previous values of rate, discount, quantity, items, remarks before each edit';
