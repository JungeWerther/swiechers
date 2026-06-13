-- The classify pipeline now runs on a DigitalOcean chat model (llama3.3-70b-instruct)
-- which can take longer than Haiku did. The edge function still completes and writes
-- back even if pg_net stops waiting, but a 30s pg_net timeout logs a false failure in
-- net._http_response. Give classify more headroom (60s); embed stays fast at 30s.
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
    timeout_milliseconds => 60000
  );
  return NEW;
end;
$function$;
