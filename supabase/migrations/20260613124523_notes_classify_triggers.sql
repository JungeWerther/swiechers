-- Fire the classify edge function asynchronously when a note is written.
create or replace function public.classify_note()
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
    url => project_url || '/functions/v1/classify',
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

create trigger classify_notes_on_insert
  after insert on public.notes
  for each row execute function public.classify_note();

-- Only re-classify when the text actually changed. This keeps the function's
-- own category/tags write (and the embed function's embedding write) from
-- re-triggering classification.
create trigger classify_notes_on_update
  after update on public.notes
  for each row
  when (
    old.title is distinct from new.title
    or old.content is distinct from new.content
  )
  execute function public.classify_note();
