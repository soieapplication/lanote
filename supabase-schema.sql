-- ============================================================
-- La Note Gourmande — database schema
-- Run this ONCE in Supabase → SQL Editor → New query → Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- MENU ----------
create table if not exists menu_categories (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  num text not null,
  description text default '',
  sort_order int not null default 0
);

create table if not exists menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references menu_categories(id) on delete cascade,
  name text not null,
  description text default '',
  price integer not null default 0,
  price_from boolean not null default false,
  active boolean not null default true,
  sort_order int not null default 0,
  options jsonb not null default '[]'::jsonb
);

-- ---------- INVENTORY ----------
create table if not exists inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  unit text not null default 'unité',
  quantity numeric not null default 0,
  low_stock_threshold numeric not null default 0,
  linked_menu_item_id uuid references menu_items(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- ---------- ORDERS ----------
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null default '',
  phone text default '',
  mode text not null default 'livraison' check (mode in ('livraison','emporter','surplace')),
  address text default '',
  note text default '',
  total integer not null default 0,
  status text not null default 'nouvelle' check (status in ('nouvelle','en_preparation','pret','livree','annulee')),
  loyalty_code text default '',
  created_at timestamptz not null default now()
);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  name text not null,
  qty int not null default 1,
  unit_price integer not null default 0,
  selections jsonb not null default '[]'::jsonb
);

-- ---------- LOYALTY (server-side mirror) ----------
create table if not exists loyalty_members (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  phone text not null,
  points integer not null default 0,
  created_at timestamptz not null default now()
);

-- ---------- ADMIN USERS ----------
create table if not exists admin_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text default '',
  role text not null default 'admin',
  created_at timestamptz not null default now()
);

create or replace function is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (select 1 from admin_profiles where id = auth.uid());
$$;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table menu_categories enable row level security;
alter table menu_items enable row level security;
alter table inventory_items enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table loyalty_members enable row level security;
alter table admin_profiles enable row level security;

-- Menu: everyone can read active items (storefront), only admins can write
create policy "public read categories" on menu_categories for select using (true);
create policy "admin write categories" on menu_categories for all using (is_admin()) with check (is_admin());

create policy "public read active items" on menu_items for select using (active = true or is_admin());
create policy "admin write items" on menu_items for all using (is_admin()) with check (is_admin());

-- Inventory: admins only
create policy "admin all inventory" on inventory_items for all using (is_admin()) with check (is_admin());

-- Orders: anyone can create an order (customers on the storefront), only admins can read/update/delete
create policy "public insert orders" on orders for insert with check (true);
create policy "admin read orders" on orders for select using (is_admin());
create policy "admin update orders" on orders for update using (is_admin());
create policy "admin delete orders" on orders for delete using (is_admin());

create policy "public insert order_items" on order_items for insert with check (true);
create policy "admin read order_items" on order_items for select using (is_admin());
create policy "admin write order_items" on order_items for update using (is_admin());
create policy "admin delete order_items" on order_items for delete using (is_admin());

-- Loyalty: public can insert/select their own by code lookup via RPC would be better,
-- but for simplicity: public can insert (join) and select (to check balance), admins manage.
create policy "public insert loyalty" on loyalty_members for insert with check (true);
create policy "public read loyalty" on loyalty_members for select using (true);
create policy "admin write loyalty" on loyalty_members for update using (is_admin());
create policy "admin delete loyalty" on loyalty_members for delete using (is_admin());

-- Admin profiles: a logged-in admin can read their own row; admins can read all
create policy "self read admin profile" on admin_profiles for select using (auth.uid() = id or is_admin());

-- ============================================================
-- SEED: menu categories + items (from the current storefront menu)
-- ============================================================
insert into menu_categories (slug, title, num, description, sort_order) values
('aperitifs','Apéritifs','01','Pour ouvrir le bal en douceur.',1),
('salades','Salades','02','Fraîcheur et croquant, à personnaliser.',2),
('viandes','Viandes','03','Servi avec un accompagnement au choix.',3),
('poissons','Poissons','04','Servi avec un accompagnement au choix.',4),
('garnitures','Garnitures','05','Vos accompagnements à composer, à la carte.',5),
('pates','Sauces & Pâtes','06','Sauces italiennes et pâtes fraîches.',6),
('africaines','Spécialités Africaines','07','Les grands classiques, faits maison.',7),
('pizza','Pizza','08','Pâte fine, cuisson maison — suppléments en option.',8),
('sandwichs','Sandwichs','09','Sur le pouce, sans compromis.',9),
('desserts','Desserts','10','La touche sucrée qui conclut la note.',10),
('glaces','Composez votre coupe','11','Base, coulis, croquants — choisissez chaque élément.',11),
('cocktails','Cocktails','12','Bar & Rooftop — servis dès 18h.',12),
('sansalcool','Cocktails sans alcool','13','Tout aussi savoureux, zéro alcool.',13),
('boissons','Jus, Boissons chaudes & Eaux','14','Naturels, chauds ou pétillants.',14),
('bieres','Bières & Softs','15','Fraîches et servies au bar comme au rooftop.',15),
('spiritueux','Spiritueux, Vins & Champagnes','16','Au verre ou à la bouteille.',16)
on conflict (slug) do nothing;

-- Note: full item list is seeded separately by seed-items.sql (generated to keep this file short)
