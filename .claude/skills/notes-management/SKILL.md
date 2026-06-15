---
name: notes-management
description: How the Supabase `notes` table and its on-write AI pipelines work — schema, the classify (Claude Haiku) and embed (DigitalOcean) triggers, Vault secrets, semantic search via match_notes, and how to change models/triggers safely. Use when working on notes storage, the classify or embed edge functions, the notes triggers, or semantic search over notes.
---

# Managing the `notes` table

The `notes` table (Supabase project `bhewgqnzhyllvxcdmjrd`) has two AI pipelines
that run automatically on write, plus a semantic-search RPC. Source of truth for
the SQL and edge functions is `supabase/` in this repo; the live project is
managed via the Supabase MCP tools (or the Supabase CLI/dashboard).

## Schema

`public.notes`:

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | PK, `gen_random_uuid()` |
| `user_id` | `uuid` | NOT NULL, FK → `auth.users`, default `auth.uid()` |
| `title` | `text` | nullable |
| `content` | `text` | nullable |
| `created_at` / `updated_at` | `timestamptz` | `updated_at` maintained by `set_updated_at()` trigger |
| `category` | `text` | **set by the classify pipeline** |
| `tags` | `text[]` | **set by the classify pipeline** |
| `embedding` | `vector(1024)` | **set by the embed pipeline**; HNSW index `notes_embedding_idx` (cosine) |

RLS is enabled. A real `auth.users` row is required to insert (the FK +
`auth.uid()` default), so you can't insert a note without a user.

## On-write pipelines

Both fire from Postgres triggers that call an edge function asynchronously via
`pg_net` (`net.http_post`). The trigger functions are `SECURITY DEFINER` and read
`project_url` + `anon_key` from Vault to authenticate the call.

### classify → `category` + `tags`
- Edge function: `classify` (`supabase/functions/classify/index.ts`).
- Model: **Claude `claude-haiku-4-5`** via the Anthropic Messages API, using
  structured outputs (`output_config.format`, json_schema) to return
  `{category, tags}` reliably.
- `category` is one of: `idea`, `task`, `reference`, `journal`, `meeting`,
  `project`, `personal`, `other` (falls back to `other`). `tags`: 1–5 lowercase
  topic strings.
- Anthropic key: Vault secret **`anthropic-key`** (read inside the function via
  `SUPABASE_DB_URL` → `vault.decrypted_secrets`).

### embed → `embedding`
- Edge function: `embed` (`supabase/functions/embed/index.ts`).
- Model: **DigitalOcean `qwen3-embedding-0.6b`** (1024-dim) via Gradient
  serverless inference, OpenAI-compatible: `POST https://inference.do-ai.run/v1/embeddings`.
- DigitalOcean key: Vault secret **`digitalocean-inference-model-key`**.
- Note: Anthropic has **no** embeddings endpoint, and DigitalOcean's `glm-5` is a
  chat model, not an embeddings model — that's why this uses a Qwen embedding model.

### Triggers (and why there's no loop)
- `classify_notes_on_insert` / `embed_notes_on_insert`: `AFTER INSERT`.
- `classify_notes_on_update`: `AFTER UPDATE ... WHEN (title or content changed)`.
- `embed_notes_on_update`: `AFTER UPDATE OF title, content`.
- Each function writes **disjoint** columns (`category`/`tags` vs `embedding`),
  and the update triggers only fire on `title`/`content` changes — so a
  function's own write-back never re-triggers either pipeline. **Preserve this
  guarding** if you add or modify triggers, or you'll create an infinite
  pg_net → function → UPDATE loop.

## Semantic search

```sql
select * from public.match_notes(query_embedding := $1, match_count := 5);
```

`match_notes` returns `(id, title, content, similarity)` ordered by cosine
similarity (`1 - (embedding <=> query)`), skipping rows with no embedding.

**The query embedding MUST come from the same model as the stored vectors**
(`qwen3-embedding-0.6b`, 1024-dim). Embed the search text with that DigitalOcean
model first, then pass the vector to `match_notes`. Mixing embedding models
produces meaningless similarity scores.

## Vault secrets used

| Secret | Used by |
|---|---|
| `project_url` | trigger functions (build the edge-function URL) |
| `anon_key` | trigger functions (auth the pg_net call) |
| `anthropic-key` | `classify` function |
| `digitalocean-inference-model-key` | `embed` function |

Keys live in Vault (not as edge-function env secrets) so both functions read
them the same way: `select decrypted_secret from vault.decrypted_secrets where name = '...'`.

## Changing things safely

- **Deploy an edge function:** Supabase MCP `deploy_edge_function` (keep
  `verify_jwt: true` — the triggers pass the anon JWT), or `supabase functions
  deploy`. Mirror the change back into `supabase/functions/<name>/index.ts`.
- **Change the classify categories:** edit the `CATEGORIES` array and the
  json_schema enum in `classify/index.ts`, redeploy. No DB change needed.
- **Change the embedding model:** if the new model's dimensionality ≠ 1024, you
  must `alter` the `embedding` column to the new `vector(N)`, recreate
  `notes_embedding_idx`, **re-embed all existing rows**, and use the same model
  for query embeddings in search. If it's still 1024 it's a drop-in (just change
  `EMBEDDING_MODEL`).
- **DDL:** use `apply_migration` and add the SQL under `supabase/migrations/`.
- **Verify a pipeline:** insert a note for an existing `auth.users` id, wait a
  few seconds (pg_net is async), then check the row; inspect failures via
  `net._http_response` or the edge-function logs (`get_logs` / dashboard).
  Clean up test notes afterward.

## Versioned markdown ingestion (`ingest_markdown_note`)

Markdown files in the repo are ingested as notes with content-hash versioning
(migrations `..._notes_markdown_versioning.sql` and `..._ci_user_scoped_grants.sql`).
Three extra columns on `notes`:

| Column | Notes |
|---|---|
| `source_path` | stable pointer to the source file (e.g. `docs/foo.md`), shared across versions; NULL for non-file notes |
| `content_hash` | **unsalted** `sha256(content)` (matches a plain `sha256sum`); the dedupe/version key |
| `version` | monotonic per `source_path` (1, then N+1 per distinct content) |

`ingest_markdown_note(p_user_id uuid, p_source_path text, p_content text, p_title default null)`
is `SECURITY DEFINER`: it computes the hash server-side, returns the existing row
if that exact content already exists for the path (no-op), else **inserts the
next version**. Append-only, so history is kept and each version is a fresh
INSERT → classify + embed fire per version. Unique indexes on
`(source_path, version)` and `(source_path, content_hash)` make re-pushes
idempotent. View `notes_current` = latest version per `source_path`.

## CI monitor + scoped `ci_user` role

`.github/workflows/markdown-to-supabase.yml` runs on push to `main`: when a
markdown file is added/changed it calls `ingest_markdown_note` per file over
`psql` (one keyhole call each), which fires classify + embed via the triggers
above. The monitor calls **no inference itself** — the DB triggers do.

CI connects as a dedicated Postgres role **`ci_user`** granted `EXECUTE` on
**only** `ingest_markdown_note` (no table access, not a superuser); the
SECURITY DEFINER function inserts on its behalf. The default
`PUBLIC`/`anon`/`authenticated` EXECUTE on that function is revoked, so the
public anon key can't call it. The connection string lives in the GitHub secret
`SUPABASE_CI_DATABASE_URL` (pooler, `sslmode=require`); rotate by recreating the
role's password and updating the secret. See `supabase/README.md` for the exact
SQL.
