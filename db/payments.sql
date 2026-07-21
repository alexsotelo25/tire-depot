-- ============================================================
-- TIRE DEPOT — Payment tracking for the owner dashboard
-- Run this in Supabase → SQL Editor AFTER roles.sql. Safe to re-run.
--
-- Adds three columns to bookings so the owner can mark a job paid,
-- record the amount, and see revenue totals in the "Paid" tab.
-- No new access rules needed — staff already have update rights,
-- and only owner/admin see the Paid tab (shop dashboard has none).
-- ============================================================

alter table public.bookings add column if not exists paid    boolean not null default false;
alter table public.bookings add column if not exists amount  numeric(10,2);
alter table public.bookings add column if not exists paid_at timestamptz;
