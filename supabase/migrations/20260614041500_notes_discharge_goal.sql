-- The prover. Given a note whose judgment is a `goal` (a question / open hole),
-- try to discharge it from the rest of the knowledge base:
--   * relational goal R(X, Y): discharged if some note links X and Y (asserts
--     atoms about both) — that note's atoms are the evidence chain.
--   * unary goal P(X): not derivable by bridging (only one endpoint), so it stays
--     open; we report any corroborating atoms about X from other notes.
-- This is deliberately honest: it discharges what the KB actually supports and
-- leaves the rest as open goals rather than fabricating proofs.
create or replace function public.discharge_goal(p_note_id uuid)
returns table(goal text, verdict text, evidence text[], reconstructed text)
language plpgsql
stable
as $$
declare
  j jsonb;
  nodes jsonb;
  root jsonb;
  endpoints text[];
  x text;
  y text;
  ev_note uuid;
  ev text[];
  fact text;
begin
  select judgment into j from public.notes where id = p_note_id;
  if j is null then
    return query select null::text, 'no judgment'::text, '{}'::text[], null::text;
    return;
  end if;

  goal := public.verbalize_judgment(j);

  if coalesce(j->>'status', '') <> 'goal' then
    return query select goal, 'not a goal (nothing to discharge)'::text, '{}'::text[], goal;
    return;
  end if;

  nodes := j -> 'nodes';
  root := nodes -> (j->>'type')::int;
  select array_agg(a->>'entity')
    into endpoints
  from jsonb_array_elements(coalesce(root->'args', '[]'::jsonb)) a;

  -- Unary (or arg-less) goal: one endpoint, nothing to bridge to. Stays open.
  if endpoints is null or array_length(endpoints, 1) < 2 then
    x := coalesce(endpoints[1], '');
    select array_agg(public.verbalize_proposition(p) order by n.created_at)
      into ev
    from public.notes n, lateral jsonb_array_elements(coalesce(n.propositions, '[]'::jsonb)) p
    where n.id <> p_note_id
      and n.title not in ('small note', 'Drawing conclusions from a note')
      and exists (
        select 1 from jsonb_array_elements(p->'args') a where a->>'entity' = x
      );
    return query select goal,
                        'open: unary claim, no inhabiting proof in the KB'::text,
                        coalesce(ev, '{}'),
                        goal;
    return;
  end if;

  -- Relational goal: look for a note that asserts atoms about BOTH endpoints.
  x := endpoints[1];
  y := endpoints[2];
  select n.id into ev_note
  from public.notes n
  where n.title not in ('small note', 'Drawing conclusions from a note')
    and exists (
      select 1 from jsonb_array_elements(n.propositions) p,
                    jsonb_array_elements(p->'args') a
      where a->>'entity' = x
    )
    and exists (
      select 1 from jsonb_array_elements(n.propositions) p,
                    jsonb_array_elements(p->'args') a
      where a->>'entity' = y
    )
  order by n.created_at
  limit 1;

  if ev_note is null then
    return query select goal,
                        'open: endpoints not linked anywhere in the KB'::text,
                        '{}'::text[],
                        goal;
    return;
  end if;

  -- Evidence = that note's atoms in order (the chain that links X to Y).
  select array_agg(public.verbalize_proposition(p) order by ord)
    into ev
  from public.notes n, lateral jsonb_array_elements(n.propositions) with ordinality as t(p, ord)
  where n.id = ev_note;

  fact := public.verbalize_proposition(root);
  return query select goal,
                      'discharged'::text,
                      coalesce(ev, '{}'),
                      upper(left(fact, 1)) || substr(fact, 2) || '.';
end;
$$;

comment on function public.discharge_goal(uuid) is
  'Goal-discharge prover: closes a relational goal R(X,Y) when a note links X and '
  'Y (returning that note''s atoms as the evidence chain and a proved-form '
  'reconstruction); leaves unary goals open with any corroborating atoms.';
