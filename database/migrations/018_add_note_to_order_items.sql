-- Migration: Add note column to order_items
-- Purpose: Allow storing item-level product notes entered in the product details dialog

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS note text;

COMMENT ON COLUMN public.order_items.note IS 'Custom product note or instruction entered when adding the product to order';
