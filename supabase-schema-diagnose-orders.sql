-- Diagnostic: run this and paste back the full result.

-- 1) Full policy detail including permissive/restrictive and the actual
--    USING / WITH CHECK expressions.
select polname, polcmd, polpermissive, polroles::regrole[]::text[] as roles,
       pg_get_expr(polqual, polrelid) as using_expr,
       pg_get_expr(polwithcheck, polrelid) as with_check_expr
from pg_policy
where polrelid = 'public.orders'::regclass;

-- 2) Table-level privileges for the anon role (separate from RLS policies —
--    Postgres requires BOTH a table grant and a passing policy).
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'orders'
order by grantee, privilege_type;

-- 3) Is RLS forced (applies even to table owner) — shouldn't matter for
--    anon, but good to confirm.
select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'public.orders'::regclass;
