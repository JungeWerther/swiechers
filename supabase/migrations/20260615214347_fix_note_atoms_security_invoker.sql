-- note_atoms was a SECURITY DEFINER view (owned by postgres, security_invoker
-- off) granted to anon/authenticated, so it ran with the owner's rights and
-- bypassed RLS: any caller with the public anon key could read every user's
-- note titles + extracted propositions via /rest/v1/note_atoms.
--
-- Make the view honor the querying user's RLS so callers only see their own
-- notes (anon sees none).
alter view public.note_atoms set (security_invoker = on);
