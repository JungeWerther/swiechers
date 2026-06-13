-- Deterministic projection of the typed `propositions` objects into a Lisp-like
-- s-expression form. Pure function of the stored jsonb (no model involved): each
-- proposition becomes `(predicate arg ...)`, with the article folded into the
-- entity token (the-fridge, a-dog) or dropped when the article is 'none'.
create or replace function public.render_sexprs(props jsonb)
returns text[]
language sql
immutable
as $$
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
$$;

comment on function public.render_sexprs(jsonb) is
  'Renders a notes.propositions jsonb array into Lisp-style s-expressions, '
  'e.g. [{"predicate":"empty","args":[{"entity":"fridge","article":"the"}]}] '
  '-> {"(empty the-fridge)"}. Immutable, so it can back a generated column.';

-- Derived, always-in-sync Lisp view of the propositions. Stored generated column
-- so it is queryable/indexable; recomputed automatically whenever propositions
-- changes (which the classify pipeline does on insert/update).
alter table public.notes
  add column if not exists propositions_sexpr text[]
  generated always as (public.render_sexprs(propositions)) stored;

comment on column public.notes.propositions_sexpr is
  'Lisp-style s-expression projection of propositions (generated, read-only). '
  'See render_sexprs(jsonb). The typed propositions column is the source of truth.';
