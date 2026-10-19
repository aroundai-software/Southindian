-- Migration: Item-level billed qty vs Tally sales
-- Run this in the Supabase SQL Editor, then run Tally sync.
--
-- Partial Tally sales (some SO items billed, others left on the order)
-- used to mark the whole sales_orders row as billed. These columns let
-- the app show Ordered / Sold / Pending per line.

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS billed_qty numeric(14, 4) NOT NULL DEFAULT 0;

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS is_partially_billed boolean NOT NULL DEFAULT false;

ALTER TABLE public.sales_orders
  ADD COLUMN IF NOT EXISTS billed_amount numeric(14, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.order_items.billed_qty IS
  'Qty billed in Tally sales vouchers linked to this sales order. pending = quantity - billed_qty.';

COMMENT ON COLUMN public.sales_orders.is_partially_billed IS
  'True when a Tally sales voucher exists against the SO but at least one line still has pending qty.';

COMMENT ON COLUMN public.sales_orders.billed_amount IS
  'Net amount billed in Tally against this SO. Used on billed/partial orders instead of full order total.';
