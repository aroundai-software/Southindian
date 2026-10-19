-- Migration: Salesman payment collections
-- Run this in the Supabase SQL Editor before using Dashboard → Collection.
--
-- Stores cash / cheque / bank / UPI / card / online receipts collected by salesmen.

CREATE TABLE IF NOT EXISTS payment_collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id text NOT NULL,
  salesman_id text NOT NULL,
  salesman_name text,
  customer_id text,
  customer_name text NOT NULL,
  amount numeric(14, 2) NOT NULL,
  collection_date date NOT NULL DEFAULT CURRENT_DATE,
  payment_method text NOT NULL,
  reference_number text,
  remarks text,
  received_from text,
  instrument_number text,
  instrument_date date,
  bank_name text,
  bank_branch text,
  ifsc_code text,
  drawer_name text,
  transfer_mode text,
  account_last4 text,
  transaction_id text,
  upi_id text,
  card_last4 text,
  card_type text,
  approval_code text,
  gateway_name text,
  wallet_name text,
  other_method_detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_collections_company
  ON payment_collections (company_id);

CREATE INDEX IF NOT EXISTS idx_payment_collections_salesman
  ON payment_collections (salesman_id, collection_date DESC);

CREATE INDEX IF NOT EXISTS idx_payment_collections_customer
  ON payment_collections (customer_name);

CREATE INDEX IF NOT EXISTS idx_payment_collections_method
  ON payment_collections (payment_method);

COMMENT ON TABLE payment_collections IS
  'Salesman collections: cash, cheque, bank transfer, UPI, card, online, wallet, other.';

-- App uses the anon key with a custom users table (not auth.uid()).
ALTER TABLE payment_collections DISABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE payment_collections TO anon, authenticated, service_role;
