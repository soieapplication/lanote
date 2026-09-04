-- ============================================================
-- La Note Gourmande — v5 migration (points held pending payment confirmation)
-- Run this in Supabase → SQL Editor after supabase-schema-v4.sql
-- ============================================================

-- Orders now track whether payment has actually been confirmed by staff.
-- Loyalty points are no longer credited at checkout — only once an admin
-- confirms the payment, via confirm_order_payment() below.
alter table orders add column if not exists payment_status text not null default 'en_attente'
  check (payment_status in ('en_attente','payee'));
alter table orders add column if not exists points_earned integer not null default 0;

-- The storefront no longer credits points directly — revoke public access
-- to the old function so it can't be called to award points before payment
-- is actually confirmed.
revoke execute on function add_loyalty_points(text, integer) from anon;

-- Admin-only: marks an order's payment as received and credits its loyalty
-- points (if any) at that point, not before. Idempotent — calling it again
-- on an already-confirmed order is a no-op.
create or replace function confirm_order_payment(p_order_id uuid)
returns integer
language plpgsql
security definer
as $$
declare
  v_order orders%rowtype;
  v_earned integer := 0;
begin
  if not is_admin() then
    raise exception 'not authorized';
  end if;

  select * into v_order from orders where id = p_order_id for update;
  if not found then
    raise exception 'order not found';
  end if;
  if v_order.payment_status = 'payee' then
    return v_order.points_earned;
  end if;

  if v_order.loyalty_code is not null and v_order.loyalty_code <> '' then
    v_earned := floor(v_order.total / 100.0)::integer;
    if v_earned > 0 then
      update loyalty_members set points = points + v_earned where code = v_order.loyalty_code;
    end if;
  end if;

  update orders set payment_status = 'payee', points_earned = v_earned where id = p_order_id;
  return v_earned;
end;
$$;
grant execute on function confirm_order_payment(uuid) to authenticated;

-- Let a client see, per past order, whether payment/points are still
-- pending or already confirmed.
create or replace function get_customer_orders(p_code text)
returns table (
  id uuid,
  mode text,
  status text,
  payment_status text,
  points_earned integer,
  total integer,
  created_at timestamptz,
  items jsonb
)
language sql
security definer
stable
as $$
  select o.id, o.mode, o.status, o.payment_status, o.points_earned, o.total, o.created_at,
    coalesce(jsonb_agg(jsonb_build_object('name', oi.name, 'qty', oi.qty, 'unit_price', oi.unit_price))
      filter (where oi.id is not null), '[]'::jsonb) as items
  from orders o
  left join order_items oi on oi.order_id = o.id
  where o.loyalty_code = p_code and p_code <> ''
  group by o.id
  order by o.created_at desc;
$$;
grant execute on function get_customer_orders(text) to anon;
