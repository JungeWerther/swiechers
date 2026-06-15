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

## Markdown → Supabase monitor (CI)

`.github/workflows/markdown-to-supabase.yml` watches pushes to `main`. When a
markdown file is **added**, the workflow runs the Claude Code GitHub Action and
asks Claude to insert each new file into the `notes` table (title = file path,
content = file body) via the Supabase MCP server. The insert fires the classify
and embed triggers above, so uploaded markdown is categorised and embedded
automatically. Only newly added `.md` files are uploaded — edits and deletions
are ignored, so existing docs aren't re-inserted.

Required repo config (Settings → Secrets and variables → Actions):

| Name | Kind | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | secret | API key the Claude Code Action runs with |
| `SUPABASE_ACCESS_TOKEN` | secret | Supabase personal access token for the MCP server |
| `SUPABASE_PROJECT_REF` | variable (optional) | defaults to `bhewgqnzhyllvxcdmjrd` |
| `SUPABASE_NOTES_USER_ID` | variable (optional) | `auth.users` id that owns inserted notes |

`notes.user_id` is `NOT NULL` with an `auth.users` FK and SQL run via the MCP
server has no `auth.uid()`, so the owner id is passed explicitly (defaulting to
the existing user).
