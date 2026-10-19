-- Migration: Item category visibility
-- Run this in the Supabase SQL Editor before using App Settings → Item Category Visibility.
--
-- company_settings.hidden_stock_group_names
--   JSON array of product ItemCategory values (e.g. SAFECON, MITSUBISHI, PROJECTS).
--   Categories in this list are hidden on order creation item-select screens.
--   Empty array = all item categories visible.

ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS hidden_stock_group_names jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN company_settings.hidden_stock_group_names IS
  'ItemCategory names hidden from order item selection. Empty = all visible.';
