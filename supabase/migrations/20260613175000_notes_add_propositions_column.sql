alter table public.notes
  add column if not exists propositions jsonb;

comment on column public.notes.propositions is
  'AI-extracted assertions as predicate-argument objects (set by the classify edge function). '
  'Each element: {"predicate": text, "args": [{"entity": text, "article": "a"|"an"|"the"|"none"}]}. '
  'The article is preserved per arg so reference/truth-function differences survive '
  '(e.g. the-dog vs a-dog vs the proper noun john with article "none").';
