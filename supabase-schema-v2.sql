-- ============================================================
-- La Note Gourmande — v2 migration (client dashboard)
-- Run this in Supabase → SQL Editor after supabase-schema.sql
-- ============================================================

-- Lets a customer look up ONLY their own orders + points using their
-- loyalty code (never a blanket "read all orders" policy for anon).
create or replace function get_customer_orders(p_code text)
returns table (
  id uuid,
  mode text,
  status text,
  total integer,
  created_at timestamptz,
  items jsonb
)
language sql
security definer
stable
as $$
  select o.id, o.mode, o.status, o.total, o.created_at,
    coalesce(jsonb_agg(jsonb_build_object('name', oi.name, 'qty', oi.qty, 'unit_price', oi.unit_price))
      filter (where oi.id is not null), '[]'::jsonb) as items
  from orders o
  left join order_items oi on oi.order_id = o.id
  where o.loyalty_code = p_code and p_code <> ''
  group by o.id
  order by o.created_at desc;
$$;

grant execute on function get_customer_orders(text) to anon;

create or replace function get_customer_points(p_code text)
returns table (name text, points integer)
language sql
security definer
stable
as $$
  select name, points from loyalty_members where code = p_code;
$$;

grant execute on function get_customer_points(text) to anon;
