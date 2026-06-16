-- The role-specific revoke (20260616065317) left a PUBLIC EXECUTE grant (the
-- `=X` ACL entry) in place, so anon/authenticated could still reach these
-- functions via PUBLIC. Remove the PUBLIC grant too.
--
-- service_role keeps its explicit grant, and triggers fire without EXECUTE, so
-- nothing legitimate is affected. (ingest_markdown_note already had no PUBLIC
-- grant by this point — it is locked to service_role and the dedicated ci_user
-- role — so it is not listed here.)
revoke execute on function public.classify_note() from public;
revoke execute on function public.embed_note() from public;
revoke execute on function public.rls_auto_enable() from public;
