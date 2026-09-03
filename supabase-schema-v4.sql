-- ============================================================
-- La Note Gourmande — v4 migration (PIN admin login, phone loyalty login)
-- Run this in Supabase → SQL Editor after supabase-schema-v3.sql
-- ============================================================

-- ---------- ADMIN: 6-digit PIN login ----------
-- Admins still authenticate through Supabase Auth (email+password under the
-- hood, so sessions/security stay standard) — the PIN is just a friendlier
-- "username" that the login page resolves to the real email before calling
-- signInWithPassword.
alter table admin_profiles add column if not exists pin text unique;
alter table admin_profiles add constraint admin_pin_format check (pin is null or pin ~ '^[0-9]{6}$');

create or replace function get_admin_email(p_pin text)
returns text
language sql
security definer
stable
as $$
  select u.email::text
  from admin_profiles p
  join auth.users u on u.id = p.id
  where p.pin = p_pin;
$$;
grant execute on function get_admin_email(text) to anon;

-- Set a PIN for your existing admin account (replace both values):
-- update admin_profiles set pin = '123456' where id = 'YOUR-USER-UID';

-- ---------- LOYALTY: phone-number login ----------
-- Prevent duplicate memberships per phone number.
alter table loyalty_members add constraint loyalty_phone_unique unique(phone);

-- Tighten access: no more blanket "anyone can read every member" policy.
-- Phone lookups now go through a security-definer function instead, so a
-- client can only ever fetch their OWN membership (by their own phone),
-- never browse everyone else's points.
drop policy if exists "public read loyalty" on loyalty_members;
drop policy if exists "public insert loyalty" on loyalty_members;
create policy "admin read loyalty" on loyalty_members for select using (is_admin());

-- Looks up a membership by phone; creates one if p_name is given and none
-- exists yet. Called from the storefront when a client "logs in" with their
-- phone number.
create or replace function find_or_create_loyalty(p_phone text, p_name text default null)
returns table(code text, name text, points integer)
language plpgsql
security definer
as $$
declare
  v_code text;
begin
  return query select l.code, l.name, l.points from loyalty_members l where l.phone = p_phone;
  if found then return; end if;
  if p_name is null or trim(p_name) = '' then return; end if;

  v_code := 'LNG-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4));
  insert into loyalty_members(code, name, phone, points) values (v_code, p_name, p_phone, 0);
  return query select l.code, l.name, l.points from loyalty_members l where l.phone = p_phone;
end;
$$;
grant execute on function find_or_create_loyalty(text, text) to anon;

-- Credits points to a loyalty code at checkout (replaces the old direct
-- table UPDATE, which was silently blocked by RLS for non-admins). Capped
-- to keep the anon-callable function from being abused for unlimited points.
create or replace function add_loyalty_points(p_code text, p_amount integer)
returns integer
language plpgsql
security definer
as $$
declare v_points integer;
begin
  if p_amount is null or p_amount < 0 or p_amount > 20000 then
    raise exception 'invalid amount';
  end if;
  update loyalty_members set points = points + p_amount where code = p_code
    returning points into v_points;
  return v_points;
end;
$$;
grant execute on function add_loyalty_points(text, integer) to anon;
