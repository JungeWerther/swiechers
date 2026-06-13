---
name: notes
description: >-
  Work with Seb's personal notes knowledge base stored in Supabase. Use when
  the user wants to capture, list, read, update, delete, or semantically search
  their notes (e.g. "save a note", "what notes do I have about X", "find my
  note on Y"). Operates on the `public.notes` table via the Supabase MCP tools.
---

# Notes

A personal knowledge base backed by a Supabase Postgres table with automatic
Voyage embeddings for semantic search.

## Project

- **Supabase project ref / `project_id`:** `bhewgqnzhyllvxcdmjrd`
- Always pass this `project_id` to the `mcp__Supabase__*` tools.

## Table: `public.notes`

| Column       | Type            | Notes                                            |
| ------------ | --------------- | ------------------------------------------------ |
| `id`         | `uuid`          | PK, auto `gen_random_uuid()`                     |
| `user_id`    | `uuid`          | FK → `auth.users`, defaults to `auth.uid()`      |
| `title`      | `text`          | nullable                                         |
| `content`    | `text`          | nullable                                         |
| `embedding`  | `vector(1024)`  | Voyage `voyage-3.5`, filled automatically        |
| `created_at` | `timestamptz`   | default `now()`                                  |
| `updated_at` | `timestamptz`   | auto-updated on edit via trigger                 |

Row Level Security is enabled: each user only sees their own notes.

## How embeddings work

Don't set `embedding` manually. An `after insert` / `after update of title,
content` trigger (`embed_note`) calls the `embed` edge function via `pg_net`,
which generates a Voyage embedding and writes it back **asynchronously**
(usually a second or two). On insert/edit the embedding is briefly `null`
until the function completes.

## Common operations

Use `mcp__Supabase__execute_sql` with `project_id` = `bhewgqnzhyllvxcdmjrd`.

### Create a note

```sql
insert into public.notes (title, content)
values ('Title here', 'Body text here')
returning id, title, created_at;
```

### List recent notes

```sql
select id, title, left(content, 120) as preview, created_at
from public.notes
order by created_at desc
limit 20;
```

### Read one note

```sql
select * from public.notes where id = '<uuid>';
```

### Update a note (re-embeds automatically)

```sql
update public.notes
set title = '<new title>', content = '<new body>'
where id = '<uuid>'
returning id, updated_at;
```

### Delete a note

```sql
delete from public.notes where id = '<uuid>';
```

### Ask a question (RAG) — easiest path

The `ask` edge function does retrieval + answer generation in one call:
embeds the question with Voyage, finds the most similar notes, and answers
with Claude (`claude-opus-4-8`) grounded in those notes. Anthropic key is
read from Vault (`anthropic-key`); Voyage key from the function env.

```
POST https://bhewgqnzhyllvxcdmjrd.supabase.co/functions/v1/ask
Authorization: Bearer <anon or user JWT>
Content-Type: application/json

{ "question": "what did I note about X?" }
```

Returns `{ "answer": "...", "sources": [{ id, title, similarity }] }`.
Prefer this for any "what do my notes say about…" request.

### Semantic search (rows only)

Use the `match_notes(query_embedding, match_count)` SQL function — it returns
the closest notes and respects RLS. The `notes_embedding_idx` HNSW index uses
cosine ops.

```sql
-- :query_embedding is a 1024-dim vector literal, e.g. '[0.01, -0.02, ...]'
select id, title, left(content, 160) as preview, similarity
from public.match_notes(:query_embedding, 5);
```

To produce `:query_embedding`, call the Voyage API
(`https://api.voyageai.com/v1/embeddings`) with `input_type: "query"`, model
`voyage-3.5`. Keyword fallback when no embedding is handy:

```sql
select id, title, left(content, 160) as preview
from public.notes
where title ilike '%term%' or content ilike '%term%'
order by created_at desc
limit 10;
```

## Notes for the agent

- Confirm destructive actions (delete / bulk update) before running them.
- After an insert/update, the embedding lands a moment later — no need to wait
  unless the user immediately wants semantic search over the new note.
- If embeddings are persistently `null`, the `VOYAGE_API_KEY` secret on the
  `embed` edge function is probably missing or invalid.
- The `ask` function needs both `VOYAGE_API_KEY` (function env) and the
  `anthropic-key` Vault secret. Anthropic has no embeddings API — embeddings
  are always Voyage; Anthropic is only used for generating the answer.
