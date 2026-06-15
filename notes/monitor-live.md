# Markdown → Supabase monitor is live

This note was added to exercise the CI monitor end to end. When a markdown
file is added or changed on `main`, a GitHub Actions workflow uploads it to the
Supabase `notes` table via the scoped `ci_user` role, calling
`ingest_markdown_note(user_id, source_path, content)`.

The insert fires the existing pipelines, so this note should arrive already
classified (category + tags) and embedded for semantic search.

Test characters to prove safe quoting: a 'single quote', a $dollar, a %percent,
and a :colon — all should round-trip verbatim.
