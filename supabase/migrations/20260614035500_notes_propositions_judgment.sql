-- Add the classify pipeline's structured outputs: propositions (predicate-arg
-- assertions) and a Curry-Howard judgment, each as jsonb (the source of truth)
-- plus a generated, read-only Lisp s-expression projection. The classify edge
-- function writes the two jsonb columns; the *_sexpr columns are derived.

-- render_node(nodes, idx, depth): render one node of a judgment's flat node list
-- (SSA form) as an s-expr, recursing through connective children. depth guards
-- against cycles. Atoms render as (predicate arg...); connectives as (op ...).
create or replace function public.render_node(nodes jsonb, idx integer, depth integer default 0)
returns text
language plpgsql
immutable
as $function$
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
$function$;

-- render_judgment(j): render a whole judgment as (status term type), prefixed
-- with a (|- (context) ...) turnstile when the judgment has hypotheses.
create or replace function public.render_judgment(j jsonb)
returns text
language plpgsql
immutable
as $function$
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
$function$;

-- render_sexprs(props): render a propositions array as an array of s-exprs, one
-- per proposition, preserving order. Each is (predicate arg...) with the article
-- folded into the entity (the-dog, a-dog) except for the bare 'none' article.
create or replace function public.render_sexprs(props jsonb)
returns text[]
language sql
immutable
as $function$
  select case
    when props is null then null
    else coalesce((
      select array_agg(sx order by p_ord)
      from (
        select
          p_ord,
          '(' || (p->>'predicate') ||
          coalesce(' ' || (
            select string_agg(
              case when a->>'article' = 'none'
                   then a->>'entity'
                   else (a->>'article') || '-' || (a->>'entity')
              end,
              ' ' order by a_ord
            )
            from jsonb_array_elements(p->'args') with ordinality as args(a, a_ord)
          ), '') || ')' as sx
        from jsonb_array_elements(props) with ordinality as ps(p, p_ord)
      ) rendered
    ), '{}')
  end;
$function$;

-- The jsonb columns are the source of truth; the *_sexpr columns are generated
-- (stored) projections that recompute whenever the jsonb changes.
alter table public.notes
  add column if not exists propositions jsonb,
  add column if not exists judgment jsonb,
  add column if not exists propositions_sexpr text[]
    generated always as (public.render_sexprs(propositions)) stored,
  add column if not exists judgment_sexpr text
    generated always as (public.render_judgment(judgment)) stored;

comment on column public.notes.propositions is 'AI-extracted assertions as predicate-argument objects (set by the classify edge function). Each element: {"predicate": text, "args": [{"entity": text, "article": "a"|"an"|"the"|"none"}]}. The article is preserved per arg so reference/truth-function differences survive (e.g. the-dog vs a-dog vs the proper noun john with article "none").';
comment on column public.notes.propositions_sexpr is 'Lisp-style s-expression projection of propositions (generated, read-only). See render_sexprs(jsonb). The typed propositions column is the source of truth.';
comment on column public.notes.judgment is 'Curry-Howard typed judgment for the note (set by the classify edge function): propositions-as-types with the note as proof term. Type is a flat node list (SSA form) since structured outputs cannot express recursive schemas. See render_judgment(jsonb).';
comment on column public.notes.judgment_sexpr is 'Lisp s-expression projection of judgment (generated, read-only). See render_judgment(jsonb). The judgment jsonb column is the source of truth.';
