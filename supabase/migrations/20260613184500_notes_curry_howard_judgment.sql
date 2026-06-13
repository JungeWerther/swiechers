-- Curry-Howard layer: per-note typed judgment (propositions-as-types, note-as-proof).
-- The note's overall logical content is a TYPE; the note is the TERM inhabiting it
-- when asserted (status=proved), a goal/hole when questioned, a hypothesis when
-- supposed, or a proof of the negation when refuted.
--
-- The type is stored as a flat node list (SSA / term-graph form) rather than a
-- nested object, because Anthropic structured outputs do not support recursive
-- json_schema. Each node is an atom (predicate + args, like propositions) or a
-- connective (arrow/prod/sum/neg) whose `children` are integer indices into the
-- same `nodes` array. Shape:
--   { "status": "proved"|"goal"|"hypothetical"|"refuted",
--     "term": text, "type": <int root idx>,
--     "context": [{"var": text, "type": <int idx>}],
--     "nodes": [{"kind": "atom"|"arrow"|"prod"|"sum"|"neg",
--                "predicate": text, "args": [{entity,article}], "children": [int]}] }
alter table public.notes
  add column if not exists judgment jsonb;

comment on column public.notes.judgment is
  'Curry-Howard typed judgment for the note (set by the classify edge function): '
  'propositions-as-types with the note as proof term. Type is a flat node list '
  '(SSA form) since structured outputs cannot express recursive schemas. '
  'See render_judgment(jsonb).';

-- Render one node of the term-graph to an s-expression, recursing into children
-- by index. Depth-guarded and total (never throws) so it is safe to back a
-- generated column.
create or replace function public.render_node(nodes jsonb, idx int, depth int default 0)
returns text
language plpgsql
immutable
as $$
declare
  node jsonb;
  kind text;
  argstr text;
  parts text[];
  op text;
begin
  if nodes is null or idx is null or depth > 64 then return null; end if;
  node := nodes -> idx;
  if node is null then return null; end if;
  kind := node ->> 'kind';

  if kind = 'atom' or kind is null then
    select string_agg(
             case when a->>'article' = 'none' then a->>'entity'
                  else (a->>'article') || '-' || (a->>'entity') end,
             ' ' order by ord)
      into argstr
    from jsonb_array_elements(coalesce(node->'args', '[]'::jsonb)) with ordinality as t(a, ord);
    return '(' || coalesce(node->>'predicate', '?') || coalesce(' ' || argstr, '') || ')';
  end if;

  op := case kind
          when 'arrow' then '->'
          when 'prod'  then '*'
          when 'sum'   then '+'
          when 'neg'   then 'not'
          else kind
        end;
  select array_agg(public.render_node(nodes, (c.value::text)::int, depth + 1) order by c.ord)
    into parts
  from jsonb_array_elements(coalesce(node->'children', '[]'::jsonb)) with ordinality as c(value, ord);
  return '(' || op || ' ' || array_to_string(coalesce(parts, '{}'), ' ') || ')';
end;
$$;

comment on function public.render_node(jsonb, int, int) is
  'Render one term-graph node (see notes.judgment) to a Lisp s-expression, '
  'recursing into children by index. Depth-guarded, total.';

-- Render a whole judgment: (status term type), wrapped in (|- (ctx...) ...) when
-- the context is non-empty. Total — returns null on any malformed input so it
-- can never block an insert via the generated column.
create or replace function public.render_judgment(j jsonb)
returns text
language plpgsql
immutable
as $$
declare
  nodes jsonb;
  body text;
  ctxstr text;
begin
  if j is null then return null; end if;
  nodes := j -> 'nodes';
  body := '(' || coalesce(j->>'status', 'proved')
            || ' ' || coalesce(j->>'term', '?')
            || ' ' || coalesce(public.render_node(nodes, (j->>'type')::int, 0), '?')
            || ')';
  select string_agg(
           '(: ' || (h->>'var') || ' '
                 || coalesce(public.render_node(nodes, (h->>'type')::int, 0), '?') || ')',
           ' ')
    into ctxstr
  from jsonb_array_elements(coalesce(j->'context', '[]'::jsonb)) as h;
  if ctxstr is not null then
    return '(|- (' || ctxstr || ') ' || body || ')';
  end if;
  return body;
exception when others then
  return null;
end;
$$;

comment on function public.render_judgment(jsonb) is
  'Render a notes.judgment to a Lisp s-expression, e.g. '
  '(proved note (-> (empty the-fridge) (buy milk))). Total (null on malformed).';

-- Generated, always-in-sync s-expression view of the judgment.
alter table public.notes
  add column if not exists judgment_sexpr text
  generated always as (public.render_judgment(judgment)) stored;

comment on column public.notes.judgment_sexpr is
  'Lisp s-expression projection of judgment (generated, read-only). '
  'See render_judgment(jsonb). The judgment jsonb column is the source of truth.';
