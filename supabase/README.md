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

Mirrors the `embed` pipeline (see below). The Anthropic key is stored in Vault
rather than as an edge-function secret, matching how `project_url` / `anon_key`
are stored.

## Notes embedding pipeline

On insert (and on edits to `title`/`content`), the `embed_note()` trigger calls
the `embed` edge function via `pg_net`. It builds a `qwen3-embedding-0.6b`
(1024-dim) embedding via DigitalOcean Gradient serverless inference
(`https://inference.do-ai.run/v1/embeddings`, OpenAI-compatible) and writes it to
`notes.embedding` (`vector(1024)`). The DigitalOcean inference key is read from
Vault (secret name `digitalocean-inference-model-key`).

> Anthropic has no embeddings endpoint, and `glm-5` on DigitalOcean is a chat
> model, not an embeddings model — hence `qwen3-embedding-0.6b`.

> Note: these files are checked in for reference. The live project is managed
> through the Supabase dashboard / MCP, so applying these via the Supabase CLI
> against the same project is not required.
