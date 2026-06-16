-- Several SECURITY DEFINER functions were EXECUTE-able by anon/authenticated,
-- so they were reachable over the public REST API (/rest/v1/rpc/...):
--   * ingest_markdown_note() let anyone insert notes as ANY user (bypassing RLS)
--   * rls_auto_enable() is an admin helper
--   * classify_note()/embed_note() are triggers that could be poked to burn
--     external API credits
--
-- Revoke the role-level grants. Triggers and event triggers still fire without
-- an EXECUTE grant, so the classify/embed pipelines and RLS automation are
-- unaffected. (A PUBLIC grant remained after this and is removed in the next
-- migration, 20260616065457_revoke_public_execute_security_definer.)
revoke execute on function public.classify_note() from anon, authenticated;
revoke execute on function public.embed_note() from anon, authenticated;
revoke execute on function public.ingest_markdown_note(uuid, text, text, text) from anon, authenticated;
revoke execute on function public.rls_auto_enable() from anon, authenticated;
