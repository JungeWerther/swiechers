-- Lock ingest_markdown_note() down to a keyhole grant for CI.
--
-- The markdown→Supabase monitor connects as a dedicated, scoped Postgres role
-- `ci_user` (created out-of-band with a login password; see the workflow header
-- in .github/workflows/markdown-to-supabase.yml). The role is granted EXECUTE on
-- ONLY this function and has no other privileges — no table access, not a
-- superuser. Because the function is SECURITY DEFINER it can still insert notes
-- on ci_user's behalf.
--
-- Postgres grants EXECUTE on new functions to PUBLIC by default, and Supabase's
-- default privileges additionally grant it to anon/authenticated/service_role.
-- That would let the public anon key call this insert function, so we revoke
-- those and re-grant only to service_role (admin) and ci_user (CI).

revoke execute on function public.ingest_markdown_note(uuid, text, text, text)
  from public, anon, authenticated;
grant  execute on function public.ingest_markdown_note(uuid, text, text, text)
  to service_role;

-- ci_user is cluster-level and may not exist in every environment (e.g. a fresh
-- local stack), so grant only when it is present.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'ci_user') then
    grant usage   on schema public to ci_user;
    grant execute on function public.ingest_markdown_note(uuid, text, text, text) to ci_user;
  end if;
end $$;
