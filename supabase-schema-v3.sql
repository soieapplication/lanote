-- ============================================================
-- La Note Gourmande — v3 migration (real-time order notifications)
-- Run this in Supabase → SQL Editor after supabase-schema-v2.sql
-- ============================================================

-- Adds the orders table to Supabase's realtime publication so the admin
-- dashboard can subscribe to new-order events live (sound + on-screen +
-- browser notification), instead of only finding out on next page load.
alter publication supabase_realtime add table orders;
