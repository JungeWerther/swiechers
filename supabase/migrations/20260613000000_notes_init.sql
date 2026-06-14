-- Initial notes schema: the base table, RLS policies, the embedding column +
-- HNSW index, the updated_at and embed triggers, and the match_notes search RPC.
-- This is the foundation the later migrations build on (category/tags, classify
-- triggers, propositions/judgment). Reconstructed from the live project so the
-- migration history can rebuild the database from scratch.

create extension if not exists vector with schema extensions;
create extension if not exists pg_net with schema extensions;

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id),
  title text,
  content text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  embedding vector(1024)
);

create index if not exists notes_user_id_idx on public.notes using btree (user_id);
-- Approximate nearest-neighbour index for cosine similarity search.
create index if not exists notes_embedding_idx on public.notes using hnsw (embedding vector_cosine_ops);

-- Row-level security: a note is only visible/writable by its owner.
alter table public.notes enable row level security;

create policy "Users can view their own notes"
  on public.notes for select using ((select auth.uid()) = user_id);
create policy "Users can insert their own notes"
  on public.notes for insert with check ((select auth.uid()) = user_id);
create policy "Users can update their own notes"
  on public.notes for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "Users can delete their own notes"
  on public.notes for delete using ((select auth.uid()) = user_id);

-- Keep updated_at current on every write.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

create trigger notes_set_updated_at
  before update on public.notes
  for each row execute function public.set_updated_at();

-- Fire the embed edge function asynchronously when a note is written. Reads the
-- project URL + anon key from Vault to authenticate the pg_net call. search_path
-- is empty so vault/net references are fully qualified.
create or replace function public.embed_note()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  project_url text;
  anon_key text;
begin
  select decrypted_secret into project_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into anon_key
    from vault.decrypted_secrets where name = 'anon_key';

  perform net.http_post(
    url => project_url || '/functions/v1/embed',
    headers => jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key,
      'apikey', anon_key
    ),
    body => jsonb_build_object('id', NEW.id),
    timeout_milliseconds => 30000
  );
  return NEW;
end;
$function$;

create trigger embed_notes_on_insert
  after insert on public.notes
  for each row execute function public.embed_note();

-- Only re-embed when the text actually changed, so the embed function's own
-- embedding write-back (and the classify write-back) don't re-trigger embedding.
create trigger embed_notes_on_update
  after update of title, content on public.notes
  for each row execute function public.embed_note();

-- Semantic search: cosine similarity over the stored embeddings. The query
-- embedding MUST come from the same model as the stored vectors (1024-dim).
create or replace function public.match_notes(query_embedding vector, match_count integer default 5)
returns table(id uuid, title text, content text, similarity double precision)
language sql
stable
as $function$
  select n.id, n.title, n.content, 1 - (n.embedding <=> query_embedding) as similarity
  from public.notes n
  where n.embedding is not null
  order by n.embedding <=> query_embedding
  limit match_count;
$function$;
