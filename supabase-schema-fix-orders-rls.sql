-- ============================================================
-- Fix: restore the policy that lets customers place orders.
-- Run this in Supabase → SQL Editor.
-- ============================================================

-- Diagnostic: list what policies currently exist on orders/order_items,
-- so we can see what's actually there before/after this fix.
select schemaname, tablename, policyname, cmd, roles
from pg_policies
where tablename in ('orders','order_items')
order by tablename, policyname;

-- Re-create the customer-insert policies (idempotent: safe if already present).
drop policy if exists "public insert orders" on orders;
create policy "public insert orders" on orders for insert with check (true);

drop policy if exists "public insert order_items" on order_items;
create policy "public insert order_items" on order_items for insert with check (true);

-- Make sure RLS itself is still on (it should be, but just in case).
alter table orders enable row level security;
alter table order_items enable row level security;
