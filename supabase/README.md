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
markdown file is **added or changed**, the workflow runs the Claude Code GitHub
Action and asks Claude to hand each file to the `ingest_markdown_note` function
over `psql` — one call per file, `source_path` = file path, `content` = file
body (bound with psql's `:'var'` so the markdown needs no escaping). Each new
version is a plain insert, so the classify and embed triggers above fire and the
version is categorised + embedded automatically. Deletions are ignored.

### Versioning (`ingest_markdown_note`)

Migration `..._notes_markdown_versioning.sql` adds three columns to `notes`:

| Column | Purpose |
|---|---|
| `source_path` | stable pointer to the file (e.g. `docs/foo.md`), shared across versions |
| `content_hash` | **unsalted** `sha256(content)` — the dedupe / version key |
| `version` | monotonic per `source_path` (1, then N+1 per distinct content) |

`ingest_markdown_note(p_user_id, p_source_path, p_content, p_title default null)`
computes the hash server-side, returns the existing row if that exact content is
already stored for the path (no-op), and otherwise inserts the next version. This
is **append-only** — history is preserved, every version gets its own embedding,
and identical re-pushes are idempotent (also backed by unique indexes on
`(source_path, version)` and `(source_path, content_hash)`). The DB digest equals
a plain `sha256sum` of the file, so it's portable and salt-free. View
`notes_current` exposes the latest version per file.

### Least-privilege CI credential (`ci_user`)

CI does **not** use a Supabase management/personal access token (those are
account-wide). It connects as a dedicated Postgres role **`ci_user`** that is
granted `EXECUTE` on **only** `ingest_markdown_note` — no table access, no other
functions, not a superuser. Because the function is `SECURITY DEFINER`, it
inserts notes on `ci_user`'s behalf without the role holding any rights on the
`notes` table. A leaked credential can do exactly one thing: ingest a note.
Migration `..._ci_user_scoped_grants.sql` also revokes the default
`PUBLIC`/`anon`/`authenticated` `EXECUTE` so the public anon key can't call it.

Create / rotate the role (run as an admin, e.g. via the SQL editor or MCP):

```sql
-- pick a fresh strong password
create role ci_user with login password '<pw>' nosuperuser nocreatedb nocreaterole;
grant usage   on schema public to ci_user;
grant execute on function public.ingest_markdown_note(uuid,text,text,text) to ci_user;
```

Then set the secret to its pooler connection string (port 6543, transaction
mode, TLS required):
`postgresql://ci_user.<project_ref>:<pw>@aws-0-<region>.pooler.supabase.com:6543/postgres?sslmode=require`

Required repo config (Settings → Secrets and variables → Actions):

| Name | Kind | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | secret | API key the Claude Code Action runs with |
| `SUPABASE_CI_DATABASE_URL` | secret | pooler connection string for the scoped `ci_user` role |
| `SUPABASE_NOTES_USER_ID` | variable (optional) | `auth.users` id that owns inserted notes |

`notes.user_id` is `NOT NULL` with an `auth.users` FK and the definer function
has no `auth.uid()`, so the owner id is passed explicitly (defaulting to the
existing user).
