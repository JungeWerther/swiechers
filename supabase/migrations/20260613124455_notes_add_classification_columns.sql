alter table public.notes
  add column if not exists category text,
  add column if not exists tags text[];

comment on column public.notes.category is 'AI-assigned category (set by the classify edge function).';
comment on column public.notes.tags is 'AI-extracted topic tags (set by the classify edge function).';
