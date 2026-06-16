-- Security regression test: anonymous / signed-in API exposure
-- =============================================================================
-- PostgREST exposes the database through the `anon` and `authenticated` roles:
--   * an RPC (`/rest/v1/rpc/<fn>`) is callable only if that role has EXECUTE on
--     the function;
--   * a table/view read (`/rest/v1/<rel>`) is allowed only via SELECT grant,
--     and the rows returned are filtered by RLS — UNLESS a view is SECURITY
--     DEFINER (security_invoker = off), which runs as the view owner and
--     bypasses the caller's RLS.
--
-- So these privilege checks ARE the test of what an outside caller (holding the
-- public anon key) can reach. The test fails loudly, listing every offender.
--
-- Run it:
--   psql "$SUPABASE_DB_URL" -f supabase/tests/security_definer_exposure_test.sql
--   (or paste into the Supabase SQL editor / MCP execute_sql)
--
-- It is read-only and safe to run against any environment.
-- =============================================================================

-- ── Check A ──────────────────────────────────────────────────────────────────
-- No SECURITY DEFINER function in an API-exposed schema may be EXECUTE-able by
-- anon or authenticated. Trigger / event-trigger functions still fire without an
-- EXECUTE grant, and intentional RPCs should require the service_role, so the
-- correct invariant is "none of them are reachable by the public API roles".
do $$
declare
  r record;
  violations text := '';
begin
  for r in
    select p.oid::regprocedure::text as fn, g.grantee
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join (values ('anon'), ('authenticated')) as g(grantee)
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege(g.grantee, p.oid, 'EXECUTE')
    order by 1, 2
  loop
    violations := violations || format(E'\n  - %s  EXECUTE-able by %s', r.fn, r.grantee);
  end loop;

  if violations <> '' then
    raise exception E'SECURITY DEFINER functions reachable by the public API:%', violations;
  end if;
end $$;

-- ── Check B ──────────────────────────────────────────────────────────────────
-- Any view exposed to anon/authenticated must run as the caller (security
-- invoker), otherwise it bypasses RLS and can leak other users' rows.
do $$
declare
  r record;
  violations text := '';
begin
  for r in
    select c.oid::regclass::text as view, g.grantee
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join (values ('anon'), ('authenticated')) as g(grantee)
    where n.nspname = 'public'
      and c.relkind = 'v'
      and has_table_privilege(g.grantee, c.oid, 'SELECT')
      -- security_invoker is a boolean reloption stored as 'on'/'off'/'true'/...
      -- depending on how it was set, so normalise via a boolean cast.
      and not coalesce((select option_value::boolean
                        from pg_options_to_table(c.reloptions)
                        where option_name = 'security_invoker'), false)
    order by 1, 2
  loop
    violations := violations || format(E'\n  - %s  readable by %s but security_invoker is off (bypasses RLS)', r.view, r.grantee);
  end loop;

  if violations <> '' then
    raise exception E'RLS-bypassing views exposed to the public API:%', violations;
  end if;
end $$;

-- ── Check C ──────────────────────────────────────────────────────────────────
-- Concrete end-to-end proof for the known offender: an unauthenticated caller
-- (role `anon`, no auth.uid()) must read zero rows from note_atoms. SET ROLE
-- inside a DO block is automatically reverted on exit.
do $$
declare
  cnt bigint;
begin
  set local role anon;
  select count(*) into cnt from public.note_atoms;
  reset role;

  if cnt <> 0 then
    raise exception 'anon read % row(s) from public.note_atoms — RLS is being bypassed', cnt;
  end if;
end $$;

-- If we reach here, nothing raised: the public API exposes no SECURITY DEFINER
-- function and no RLS-bypassing view.
do $$ begin raise notice 'OK: no anon-exposed SECURITY DEFINER functions or RLS-bypassing views'; end $$;
