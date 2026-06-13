# Supabase

Database migrations and edge functions for the `notes` table.

## Notes AI classification pipeline

On insert (and on edits to `title`/`content`), a Postgres trigger calls the
`classify` edge function asynchronously via `pg_net`. The function:

1. Reads the note's `title` + `content`.
2. Reads the Anthropic API key from Supabase Vault (secret name `anthropic-key`).
3. Calls Claude Haiku (`claude-haiku-4-5`) with structured JSON output to pick a
   `category` (from a fixed set) and 1-5 topic `tags`.
4. Writes `category` and `tags` back to the row.

The update trigger only fires when `title`/`content` actually change, so the
function's own write-back doesn't re-trigger it (same guarding the `embed`
function relies on via `AFTER UPDATE OF title, content`).

Mirrors the existing `embed` pipeline (Voyage embeddings). The Anthropic key
is stored in Vault rather than as an edge-function secret, matching how
`project_url` / `anon_key` are stored.

> Note: these files are checked in for reference. The live project is managed
> through the Supabase dashboard / MCP, so applying these via the Supabase CLI
> against the same project is not required.
