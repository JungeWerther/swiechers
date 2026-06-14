-- Reconstruction layer: turn the structured forms back into sentences (the
-- inverse of the classify extraction). Plus note_atoms, a flat substrate for
-- reasoning over the propositions across the whole knowledge base.

-- An entity phrase: fold the article back out, un-hyphenate multi-word entities.
-- {entity:'loss-of-meaning',article:'the'} -> 'the loss of meaning'.
create or replace function public.verbalize_phrase(arg jsonb)
returns text
language sql
immutable
as $$
  select case
    when arg is null then ''
    when coalesce(arg->>'article','none') = 'none' then replace(arg->>'entity', '-', ' ')
    else (arg->>'article') || ' ' || replace(arg->>'entity', '-', ' ')
  end;
$$;

-- Verbalize one type node to English, recursing into children by index.
-- atom: 0 args -> predicate; 1 arg -> "predicate phrase" (verb-first reads best
-- for this data); >=2 args -> "subject predicate object...". Connectives map to
-- if/then, and, or, not. Depth-guarded; null on a bad index (callers coalesce).
create or replace function public.verbalize_node(nodes jsonb, idx int, depth int default 0)
returns text
language plpgsql
immutable
as $$
declare
  node jsonb;
  kind text;
  pred text;
  nargs int;
  rest text;
  parts text[];
begin
  if nodes is null or idx is null or depth > 64 then return null; end if;
  node := nodes -> idx;
  if node is null then return null; end if;
  kind := node ->> 'kind';

  if kind is null or kind = 'atom' then
    pred := replace(replace(coalesce(node->>'predicate', '?'), '-', ' '), '_', ' ');
    nargs := coalesce(jsonb_array_length(node->'args'), 0);
    if nargs = 0 then
      return pred;
    elsif nargs = 1 then
      return trim(pred || ' ' || public.verbalize_phrase(node->'args'->0));
    else
      select string_agg(public.verbalize_phrase(value), ' ' order by ord)
        into rest
      from jsonb_array_elements(node->'args') with ordinality as t(value, ord)
      where ord >= 2;
      return trim(public.verbalize_phrase(node->'args'->0) || ' ' || pred || ' ' || coalesce(rest, ''));
    end if;
  end if;

  select array_agg(coalesce(public.verbalize_node(nodes, (c.value::text)::int, depth + 1), '?') order by c.ord)
    into parts
  from jsonb_array_elements(coalesce(node->'children', '[]'::jsonb)) with ordinality as c(value, ord);
  parts := coalesce(parts, '{}');

  return case kind
    when 'arrow' then 'if ' || coalesce(parts[1], '?') || ', then ' || coalesce(parts[2], '?')
    when 'prod'  then array_to_string(parts, ' and ')
    when 'sum'   then array_to_string(parts, ' or ')
    when 'neg'   then 'not (' || coalesce(parts[1], '?') || ')'
    else array_to_string(parts, ' ' || kind || ' ')
  end;
end;
$$;

-- Verbalize a whole judgment, reading the mood off `status`: proved -> a
-- statement, goal -> a question, refuted -> a denial, hypothetical -> a supposition.
create or replace function public.verbalize_judgment(j jsonb)
returns text
language plpgsql
immutable
as $$
declare
  nodes jsonb;
  core text;
  status text;
  ctxt text;
  result text;
begin
  if j is null then return null; end if;
  nodes := j -> 'nodes';
  core := coalesce(public.verbalize_node(nodes, (j->>'type')::int, 0), '?');
  status := coalesce(j->>'status', 'proved');

  if status = 'goal' then
    result := 'is it the case that ' || core || '?';
  elsif status = 'refuted' then
    result := 'it is not the case that ' || core || '.';
  elsif status = 'hypothetical' then
    select string_agg(coalesce(public.verbalize_node(nodes, (h->>'type')::int, 0), '?'), ' and ')
      into ctxt
    from jsonb_array_elements(coalesce(j->'context', '[]'::jsonb)) as h;
    result := 'suppose ' || coalesce(ctxt, 'something') || '; then ' || core || '.';
  else
    result := core || '.';
  end if;

  return upper(left(result, 1)) || substr(result, 2);
exception when others then
  return null;
end;
$$;

-- Convenience: verbalize a single proposition object ({predicate, args}).
create or replace function public.verbalize_proposition(p jsonb)
returns text
language sql
immutable
as $$
  select public.verbalize_node(jsonb_build_array(p), 0, 0);
$$;

-- Flat reasoning substrate: one row per (note, proposition), with the predicate
-- and the list of entity tokens it mentions. Join/aggregate over this to reason.
create or replace view public.note_atoms as
select
  n.id as note_id,
  n.title,
  n.created_at,
  p->>'predicate' as predicate,
  array(
    select a->>'entity'
    from jsonb_array_elements(coalesce(p->'args', '[]'::jsonb)) a
  ) as entities
from public.notes n,
     lateral jsonb_array_elements(coalesce(n.propositions, '[]'::jsonb)) p;

comment on view public.note_atoms is
  'One row per (note, proposition): predicate + entity tokens. The substrate for '
  'reasoning over the knowledge base (entity joins, goal discharge, tensions).';
