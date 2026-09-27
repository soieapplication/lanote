-- ============================================================
-- La Note Gourmande — v6 migration (table reservations, loyalty reward claims)
-- Run this in Supabase → SQL Editor after supabase-schema-v5.sql
-- ============================================================

-- ---------- TABLE RESERVATIONS ----------
create table if not exists reservations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  email text not null,
  reservation_time timestamptz not null,
  guests integer not null default 2,
  status text not null default 'en_attente' check (status in ('en_attente','confirmee','annulee')),
  created_at timestamptz not null default now()
);

alter table reservations enable row level security;

create policy "public insert reservations" on reservations for insert with check (true);
create policy "admin read reservations" on reservations for select using (is_admin());
create policy "admin update reservations" on reservations for update using (is_admin());
create policy "admin delete reservations" on reservations for delete using (is_admin());

alter publication supabase_realtime add table reservations;

-- ---------- LOYALTY REWARD CLAIMS ----------
-- Tracks which tier rewards a member has already claimed, so a reward can't
-- be claimed twice, and gives staff a short code to verify in person.
create table if not exists loyalty_claims (
  id uuid primary key default gen_random_uuid(),
  loyalty_code text not null,
  tier text not null check (tier in ('argent','or')),
  claim_code text not null,
  redeemed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (loyalty_code, tier)
);

alter table loyalty_claims enable row level security;
create policy "admin all loyalty_claims" on loyalty_claims for all using (is_admin()) with check (is_admin());

-- Lets a client claim a tier reward once they've reached the points
-- threshold. Idempotent per (code, tier) via the unique constraint above.
create or replace function claim_loyalty_reward(p_code text, p_tier text)
returns table(claim_code text, already_claimed boolean)
language plpgsql
security definer
as $$
declare
  v_points integer;
  v_min integer;
  v_existing text;
  v_code text;
begin
  if p_tier not in ('argent','or') then
    raise exception 'invalid tier';
  end if;
  v_min := case p_tier when 'argent' then 500 when 'or' then 1500 end;

  select points into v_points from loyalty_members where code = p_code;
  if v_points is null or v_points < v_min then
    raise exception 'not eligible';
  end if;

  select loyalty_claims.claim_code into v_existing from loyalty_claims
    where loyalty_code = p_code and tier = p_tier;
  if v_existing is not null then
    return query select v_existing, true;
    return;
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into loyalty_claims (loyalty_code, tier, claim_code) values (p_code, p_tier, v_code);
  return query select v_code, false;
end;
$$;
grant execute on function claim_loyalty_reward(text, text) to anon;

-- Lets a client check which tiers they've already claimed (so the button
-- can show "Déjà réclamé" instead of letting them claim twice).
create or replace function get_loyalty_claims(p_code text)
returns table(tier text, claim_code text, redeemed boolean)
language sql
security definer
stable
as $$
  select tier, claim_code, redeemed from loyalty_claims where loyalty_code = p_code;
$$;
grant execute on function get_loyalty_claims(text) to anon;
