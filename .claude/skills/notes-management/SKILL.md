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
| `propositions` | `jsonb` | **set by the classify pipeline**; extracted assertions as predicate-argument objects |
| `propositions_sexpr` | `text[]` | **generated** (STORED) from `propositions` via `render_sexprs()`; Lisp s-expression form, read-only |
| `judgment` | `jsonb` | **set by the classify pipeline**; Curry-Howard typed judgment (propositions-as-types, note-as-proof) |
| `judgment_sexpr` | `text` | **generated** (STORED) from `judgment` via `render_judgment()`; Lisp s-expression form, read-only |
| `embedding` | `vector(1024)` | **set by the embed pipeline**; HNSW index `notes_embedding_idx` (cosine) |

RLS is enabled. A real `auth.users` row is required to insert (the FK +
`auth.uid()` default), so you can't insert a note without a user.

## On-write pipelines

Both fire from Postgres triggers that call an edge function asynchronously via
`pg_net` (`net.http_post`). The trigger functions are `SECURITY DEFINER` and read
`project_url` + `anon_key` from Vault to authenticate the call.

### classify → `category` + `tags` + `propositions` + `judgment`
- Edge function: `classify` (`supabase/functions/classify/index.ts`).
- Model: **DigitalOcean `llama3.3-70b-instruct`** via Gradient serverless
  inference (OpenAI-compatible `POST https://inference.do-ai.run/v1/chat/completions`),
  using JSON mode (`response_format: {type: "json_object"}`) to return
  `{category, tags, propositions, judgment}`. There is **no** server-side schema
  enforcement, so the system prompt spells out the exact shape and the
  `normalize*()` helpers defensively coerce the result (`stripJsonFences` handles
  models that wrap output in code fences). Set via `CHAT_MODEL` in
  `classify/index.ts` — **use a non-reasoning instruct model**: reasoning models
  like `glm-5` take ~2 min and blow the trigger's pg_net timeout. Even
  `llama3.3-70b-instruct` can run >30s, so the classify trigger's
  `timeout_milliseconds` was raised to 60000 (the function still completes and
  writes back even if pg_net stops waiting).
- `category` is one of: `idea`, `task`, `reference`, `journal`, `meeting`,
  `project`, `personal`, `other` (falls back to `other`). `tags`: 1–5 lowercase
  topic strings.
- `propositions`: every assertion the note makes (claims that can be true/false;
  questions and commands are skipped), each as a predicate-argument object:
  `{"predicate": "<base-form property/relation>", "args": [{"entity": "<lowercase
  noun phrase, multi-word hyphenated>", "article": "a"|"an"|"the"|"none"}]}`.
  Stored as `jsonb`. **The article is preserved per arg on purpose** — `the-dog`
  (definite) and `a-dog` (indefinite) are distinct references with different
  truth-functions, and `none` covers proper nouns/pronouns/plurals/mass nouns.
  Relations are n-ary: `"John loves Mary"` → `{predicate: loves, args: [john/none,
  mary/none]}`. `normalizePropositions()` in the function defensively drops
  malformed entries. To change the representation, edit the system prompt's
  shape spec in `classify/index.ts` and redeploy (no DB change unless the
  column type changes).
- `propositions_sexpr` is a **generated** `text[]` column: a pure Lisp-style
  projection of `propositions` via the `IMMUTABLE` SQL function
  `public.render_sexprs(jsonb)` — each proposition becomes `(predicate arg ...)`
  with the article folded into the entity token (`the-fridge`, `a-dog`) or
  dropped for `none`. It is read-only and always in sync (Postgres recomputes it
  whenever `propositions` changes); no model is involved. Edit `render_sexprs`
  (see `migrations/…_notes_propositions_sexpr.sql`) to change the surface syntax.
- `judgment` is the **Curry-Howard** layer: one typed judgment per note —
  propositions-as-types with the note as proof term. `status` is the
  inhabitation/mood (`proved` = note is the witness, `goal` = questioned/no
  witness, `hypothetical` = supposed, `refuted` = proof of the negation); the
  type is a **flat node list (SSA form)** because structured outputs can't
  express recursive json_schema — each node is an `atom` (predicate+args) or a
  connective (`arrow` `→`, `prod` `∧`, `sum` `∨`, `neg` `¬`) whose `children` are
  integer indices into `nodes`. Code validates indices and drops the whole
  judgment (→ null) if malformed. `judgment_sexpr` is the **generated** Lisp
  projection via `public.render_judgment(jsonb)` (which recurses through
  `render_node(nodes, idx, depth)`), e.g.
  `(proved note (-> (empty the-fridge) (buy milk)))`. Both renderers are
  `IMMUTABLE` and total (null on malformed) so they can safely back generated
  columns. See `migrations/…_notes_curry_howard_judgment.sql`.
- DigitalOcean key: Vault secret **`digitalocean-inference-model-key`** — the
  **same** secret the embed function uses (read inside the function via
  `SUPABASE_DB_URL` → `vault.decrypted_secrets`). Classify no longer uses
  Anthropic.

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
- Each function writes **disjoint** columns
  (`category`/`tags`/`propositions`/`judgment` vs `embedding`),
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

## Reconstruction & reasoning

The classify pipeline runs text → structure (propositions / judgment); these
functions run the **inverse and the reasoning** over it (see
`migrations/…_notes_reconstruct_and_reason.sql`):

- `verbalize_phrase(jsonb)` / `verbalize_node(nodes, idx)` / `verbalize_judgment(jsonb)`
  / `verbalize_proposition(jsonb)` — deterministic **structure → English**
  reconstruction (the inverse grammar of extraction). `verbalize_judgment` reads
  the mood off `status`: `proved` → a statement, `goal` → a question, `refuted`
  → a denial, `hypothetical` → a supposition. Crude but model-free; for fluent
  prose, hand the structure to the DO chat model instead.
- `note_atoms` (view) — one row per `(note, proposition)` with `predicate` +
  `entities[]`. The substrate for reasoning: entity joins (aggregate all atoms
  whose `entities` include `myself`/`i` → a self-model), goal discharge, tension
  detection (conflicting predicates on the same entity).
- `discharge_goal(note_id uuid)` — the **prover**. For a note whose judgment is a
  `goal`, returns `(goal, verdict, evidence[], reconstructed)`. A relational goal
  `R(X,Y)` is *discharged* if a note links X and Y (that note's atoms are the
  evidence chain, and `reconstructed` is the proved-form sentence); a unary goal
  `P(X)` stays *open* (one endpoint, nothing to bridge) with any corroborating
  atoms. Deliberately honest — it never fabricates a proof.
- **`verbalize` edge function** (`supabase/functions/verbalize/index.ts`) — the
  *fluent* counterpart to the deterministic `verbalize_*` SQL: `POST {sexpr,
  gloss?}` → `{sentence}`, rendered by the DO chat model with the mood preserved
  (`goal` → a question, `proved` → a statement). Use it when a program produced a
  structure and you want natural prose, not the crude SQL gloss.

Full loop: `text → [classify] → propositions/judgment → [discharge_goal / reasoning
over note_atoms] → new structure → [verbalize_* or the verbalize fn] → text`.

## Vault secrets used

| Secret | Used by |
|---|---|
| `project_url` | trigger functions (build the edge-function URL) |
| `anon_key` | trigger functions (auth the pg_net call) |
| `digitalocean-inference-model-key` | **both** `classify` (chat) and `embed` (embeddings) |

Keys live in Vault (not as edge-function env secrets) so both functions read
them the same way: `select decrypted_secret from vault.decrypted_secrets where name = '...'`.

## Changing things safely

- **Deploy an edge function:** Supabase MCP `deploy_edge_function` (keep
  `verify_jwt: true` — the triggers pass the anon JWT), or `supabase functions
  deploy`. Mirror the change back into `supabase/functions/<name>/index.ts`.
- **Change the classify categories:** edit the `CATEGORIES` array in
  `classify/index.ts` (it's interpolated into the system prompt), redeploy. No DB
  change needed.
- **Change the classify model:** edit `CHAT_MODEL` in `classify/index.ts` to any
  DO chat slug (`GET https://inference.do-ai.run/v1/models` lists them), redeploy.
  Keep it a **non-reasoning** instruct model so it finishes well within the
  trigger timeout.
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
