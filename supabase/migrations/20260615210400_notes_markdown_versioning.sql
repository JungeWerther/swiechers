-- Content-hash-keyed versioning for file-sourced notes.
-- source_path is the stable pointer (the file); content_hash (unsalted sha256)
-- is the dedupe/version key; version is monotonic per source_path. Ingestion is
-- append-only: each distinct content for a path is a new row, so the existing
-- classify + embed INSERT triggers encode every version automatically.

alter table public.notes
  add column if not exists source_path  text,
  add column if not exists content_hash text,
  add column if not exists version      integer;

comment on column public.notes.source_path  is 'Stable pointer to the source file (e.g. docs/foo.md); shared across all versions of that file. NULL for notes not sourced from a file.';
comment on column public.notes.content_hash is 'Unsalted sha256 hex digest of content; the dedupe/version key for file-sourced notes.';
comment on column public.notes.version      is 'Monotonic version per source_path (1 = first ingest, N+1 per distinct content_hash).';

-- One row per (file, version); one row per (file, content) so identical
-- re-pushes are idempotent at the DB level.
create unique index if not exists notes_source_path_version_key
  on public.notes (source_path, version)
  where source_path is not null;

create unique index if not exists notes_source_path_hash_key
  on public.notes (source_path, content_hash)
  where source_path is not null;

-- Latest version per source file.
create or replace view public.notes_current
  with (security_invoker = true) as
  select distinct on (source_path) *
    from public.notes
   where source_path is not null
   order by source_path, version desc;

-- Append-only, hash-guarded ingest. Computes the unsalted sha256 server-side,
-- returns the existing row when the same content already exists for the path,
-- otherwise inserts the next version. The plain INSERT fires classify + embed.
create or replace function public.ingest_markdown_note(
  p_user_id     uuid,
  p_source_path text,
  p_content     text,
  p_title       text default null
) returns public.notes
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_row  public.notes;
  v_next integer;
begin
  v_hash := encode(extensions.digest(convert_to(p_content, 'UTF8'), 'sha256'), 'hex');

  -- Same content already stored for this path -> no new version.
  select * into v_row
    from public.notes
   where source_path = p_source_path
     and content_hash = v_hash
   limit 1;
  if found then
    return v_row;
  end if;

  select coalesce(max(version), 0) + 1 into v_next
    from public.notes
   where source_path = p_source_path;

  insert into public.notes (user_id, title, content, source_path, content_hash, version)
  values (p_user_id, coalesce(p_title, p_source_path), p_content, p_source_path, v_hash, v_next)
  returning * into v_row;

  return v_row;
end;
$function$;

grant execute on function public.ingest_markdown_note(uuid, text, text, text) to service_role, authenticated;
