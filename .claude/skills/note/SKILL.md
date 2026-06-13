---
name: note
description: Create a note in the Supabase `notes` table from the text the user provides. Use when the user invokes `/note <text>` (or otherwise explicitly asks to take/jot/save a note). Inserts the row; the classify + embed pipelines then fill category, tags, propositions and embedding automatically.
---

# Taking a note

Invoked as `/note <text>`. The text after the command is the note. Your job is to
insert one row into `public.notes`; everything else (category, tags,
propositions, embedding) is filled in automatically by the on-write pipelines —
do **not** set those columns yourself.

Project: `bhewgqnzhyllvxcdmjrd`. For how the downstream pipelines work, see the
`notes-management` skill — but you don't need it just to take a note.

## Steps

1. **Parse the input** into `title` + `content`:
   - If the user wrote an explicit `title: ...` / `body: ...`, or a `<title> — <body>`
     / `<title>: <body>` split on the first line, honor it.
   - Otherwise put the whole text in `content` and derive a short `title`
     (≤ 6 words, no trailing punctuation) that summarizes it. If the note is
     itself a few words, the title may equal the content.
   - Never invent facts that aren't in the user's text.

2. **Resolve the owner.** A row needs a real `auth.users` id (FK + RLS), so pick
   one — prefer Seb's account, fall back to the only/oldest user:
   ```sql
   select id from auth.users
   order by (email = 'seb@swiechers.nl') desc, created_at asc
   limit 1;
   ```
   If there are no users, stop and tell the user — a note can't be inserted
   without one.

3. **Insert the note** (only `user_id`, `title`, `content`):
   ```sql
   insert into public.notes (user_id, title, content)
   values (:user_id, :title, :content)
   returning id;
   ```
   Use the Supabase MCP `execute_sql` against project `bhewgqnzhyllvxcdmjrd`.

4. **Confirm.** Report the new note `id` and the title/content you stored. The
   classify and embed triggers run **asynchronously** (a few seconds), so
   category/tags/propositions/embedding won't be populated in the same instant.

5. **(Optional) Show the AI fields.** Only if the user wants to see them, wait a
   few seconds, then read them back and display:
   ```sql
   select category, tags, jsonb_pretty(propositions) as propositions
   from public.notes where id = :id;
   ```

## Notes

- This skill **creates** notes. Editing the schema, classify/embed functions, or
  triggers is the `notes-management` skill's job.
- Keep it to a single insert per invocation unless the user clearly asks for
  several notes.
