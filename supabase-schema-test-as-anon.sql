-- Simulates an anon-role insert directly in the database, bypassing the
-- API gateway entirely, to tell us whether this is a Postgres RLS problem
-- or something in Supabase's API layer.
set role anon;
insert into orders (customer_name, mode, total, loyalty_code)
values ('SQL role test', 'emporter', 999, '')
returning id, customer_name;
reset role;
