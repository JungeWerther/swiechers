-- "Related notes" / "more like this": given a note, return its nearest
-- neighbors by cosine distance. Reuses the source note's stored embedding,
-- so it makes no model calls and rides the existing notes_embedding_idx (HNSW).
-- Mirrors public.match_notes, but the query vector comes from a stored row.
create or replace function public.match_related_notes(
  source_id uuid,
  match_count integer default 5
)
returns table (id uuid, title text, content text, similarity double precision)
language sql
stable
as $$
  select n.id, n.title, n.content, 1 - (n.embedding <=> src.embedding) as similarity
  from public.notes n,
       (select embedding from public.notes where id = source_id) src
  where n.id <> source_id
    and n.embedding is not null
    and src.embedding is not null
  order by n.embedding <=> src.embedding
  limit match_count;
$$;

comment on function public.match_related_notes(uuid, integer) is
  'Returns the notes most similar to source_id by cosine similarity of their embeddings (excludes the source note and un-embedded rows).';
