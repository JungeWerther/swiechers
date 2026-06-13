---
name: notes-management
description: How the Supabase `notes` table and its on-write AI pipelines work — schema, the classify (DigitalOcean glm-5) and embed (DigitalOcean qwen3) triggers, Vault secrets, semantic search via match_notes, and how to change models/triggers safely. Use when working on notes storage, the classify or embed edge functions, the notes triggers, or semantic search over notes.
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
| `propositions` | `jsonb` | **set by the classify pipeline**; extracted assertions as predicate-argument objects (see below) |
| `propositions_sexpr` | `text[]` | **generated, read-only**; Lisp-style s-expr projection of `propositions` via `render_sexprs(jsonb)` |
| `judgment` | `jsonb` | **set by the classify pipeline**; Curry-Howard typed judgment (propositions-as-types, note-as-proof) |
| `judgment_sexpr` | `text` | **generated, read-only**; Lisp-style s-expr projection of `judgment` via `render_judgment(jsonb)` |
| `embedding` | `vector(1024)` | **set by the embed pipeline**; HNSW index `notes_embedding_idx` (cosine) |

RLS is enabled. A real `auth.users` row is required to insert (the FK +
`auth.uid()` default), so you can't insert a note without a user.

The two `*_sexpr` columns are **generated** (read-only) projections — the
`jsonb` columns (`propositions`, `judgment`) are the source of truth. Edit the
jsonb, not the s-expr.

## On-write pipelines

Both fire from Postgres triggers that call an edge function asynchronously via
`pg_net` (`net.http_post`). The trigger functions are `SECURITY DEFINER` and read
`project_url` + `anon_key` from Vault to authenticate the call.

### classify → `category` + `tags` + `propositions` + `judgment`
- Edge function: `classify` (`supabase/functions/classify/index.ts`).
- Model: **DigitalOcean `glm-5`** via Gradient serverless inference,
  OpenAI-compatible chat completions: `POST https://inference.do-ai.run/v1/chat/completions`.
  There is **no** server-side schema enforcement here — the function asks for
  `response_format: { type: 'json_object' }`, spells the exact shape out in the
  prompt, and the `normalize*()` helpers defensively coerce/validate the result
  (dropping malformed propositions and storing `null` for a malformed judgment).
- DigitalOcean key: Vault secret **`digitalocean-inference-model-key`** (the same
  secret the embed function uses), read inside the function via
  `SUPABASE_DB_URL` → `vault.decrypted_secrets`.
- The function writes all four columns in one `UPDATE`. On empty note text it
  clears `category`, `tags`, `propositions`, and `judgment` to `null`.

It returns four things:
- **`category`** — one of `idea`, `task`, `reference`, `journal`, `meeting`,
  `project`, `personal`, `other` (falls back to `other`).
- **`tags`** — 1–5 lowercase topic strings.
- **`propositions`** — every assertion the note makes, as
  `{ predicate, args: [{ entity, article }] }`. `predicate` is the base-form
  property/relation; each `arg` is a lowercase (hyphenated) noun phrase plus its
  surface `article` (`a` | `an` | `the` | `none`). The article is kept because it
  changes reference (`the-dog` ≠ `a-dog`); `none` covers proper nouns, pronouns,
  plurals, and mass nouns.
- **`judgment`** — a Curry-Howard reading of the whole note (propositions-as-types,
  the note as proof term): `{ status, term, type, context, nodes }`.
  - `status` (the "mood"): `proved` (note witnesses the type, `term: "note"`),
    `goal` (questioned, no witness, `term: "?"`), `hypothetical` (supposed),
    `refuted` (denied).
  - `nodes` is a flat node list (SSA form, because structured outputs can't
    express recursive schemas); each node `kind` is `atom` (predicate+args) or a
    connective `arrow` / `prod` / `sum` / `neg` whose `children` are integer
    indices into `nodes`. `type` is the root node index; `context` holds
    hypotheses as `{ var, type }`.

To adjust the schema/vocabulary, edit the `CATEGORIES`, `ARTICLES`, `KINDS`,
`STATUSES` arrays and the prompt in `classify/index.ts`, then redeploy.

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
- Each function writes **disjoint** columns (`category`/`tags`/`propositions`/
  `judgment` vs `embedding`), and the update triggers only fire on
  `title`/`content` changes — so a function's own write-back never re-triggers
  either pipeline. **Preserve this guarding** if you add or modify triggers, or
  you'll create an infinite pg_net → function → UPDATE loop. (The generated
  `*_sexpr` columns recompute automatically and never trigger anything.)

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
| `digitalocean-inference-model-key` | **both** the `classify` and `embed` functions |

Keys live in Vault (not as edge-function env secrets) so both functions read
them the same way: `select decrypted_secret from vault.decrypted_secrets where name = '...'`.
(The `anthropic-key` secret is no longer used — classify moved off the Anthropic
API to DigitalOcean glm-5 — so it can be left in Vault or removed.)

## Changing things safely

- **Deploy an edge function:** Supabase MCP `deploy_edge_function` (keep
  `verify_jwt: true` — the triggers pass the anon JWT), or `supabase functions
  deploy`. Mirror the change back into `supabase/functions/<name>/index.ts`.
- **Change the classify categories/vocabulary:** edit the `CATEGORIES` (and, for
  propositions/judgment, `ARTICLES` / `KINDS` / `STATUSES`) arrays and the prompt
  in `classify/index.ts`, redeploy. No DB change needed for category/tag/jsonb
  content.
- **Change the classify model:** change `CHAT_MODEL` in `classify/index.ts`
  (`GET https://inference.do-ai.run/v1/models` lists the slugs) and redeploy.
  Any chat model that can emit the JSON object works — the `normalize*()` helpers
  guard the output. No DB change needed.
- **Change the propositions/judgment shape:** the `propositions_sexpr` and
  `judgment_sexpr` columns are generated from `render_sexprs(jsonb)` /
  `render_judgment(jsonb)`. If you change the jsonb shape, update those SQL
  functions (and the `normalize*()` validators) so the projections still render.
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
