-- Migration: Add ItemCategory to products
-- Date: 2026-09-09
-- Purpose: Store the Tally stock-group parent (Under).
--          ItemParent = stock group of the item (e.g. KAMPTEC-DBS)
--          ItemCategory = that group's parent (e.g. KAMPTEC)

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS "ItemCategory" text NULL;

COMMENT ON COLUMN public.products."ItemCategory" IS
  'Parent stock group of ItemParent from Tally (Under). Example: ItemParent=KAMPTEC-DBS, ItemCategory=KAMPTEC';

CREATE INDEX IF NOT EXISTS idx_products_item_category
  ON public.products ("ItemCategory");
