-- ============================================================
-- La Note Gourmande — v7 migration (seating preference on reservations)
-- Run this in Supabase → SQL Editor after supabase-schema-v6.sql
-- ============================================================

alter table reservations add column if not exists seating_preference text
  not null default 'restaurant'
  check (seating_preference in ('rooftop','vip','rdc'));
