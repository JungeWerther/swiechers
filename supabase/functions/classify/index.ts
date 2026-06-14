// Classifies a single note row with DigitalOcean glm-5 and writes category, tags,
// propositions + a Curry-Howard judgment back. Invoked asynchronously by a
// Postgres trigger via pg_net on insert/update.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

// DigitalOcean Gradient serverless inference (OpenAI-compatible chat completions),
// same endpoint family + Vault key as the embed function. glm-5 is a strong, cheap
// chat model. To swap models, change CHAT_MODEL (GET /v1/models lists the slugs).
const CHAT_MODEL = 'glm-5'
const DO_CHAT_URL = 'https://inference.do-ai.run/v1/chat/completions'
const CATEGORIES = [
  'idea',
  'task',
  'reference',
  'journal',
  'meeting',
  'project',
  'personal',
  'other',
] as const

// Surface article of an entity. 'none' covers proper nouns, pronouns, plurals
// and mass nouns that carry no article. We keep the article because it changes
// reference / truth-function: 'the-dog' (specific) and 'a-dog' (indefinite) are
// distinct entities even when the predicate is identical.
const ARTICLES = ['a', 'an', 'the', 'none'] as const

// Curry-Howard judgment vocabulary. A note's logical content is a TYPE; `status`
// is the inhabitation status (the "mood"): proved = the note is the proof term;
// goal = a questioned type with no witness; hypothetical = supposed in context;
// refuted = a proof of its negation. Connectives are type formers.
const KINDS = ['atom', 'arrow', 'prod', 'sum', 'neg'] as const
const STATUSES = ['proved', 'goal', 'hypothetical', 'refuted'] as const

// Built-in env var: full-access connection string for this project's database.
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!)

interface Arg {
  entity: string
  article: string
}

interface Proposition {
  predicate: string
  args: Arg[]
}

// One node of the type term-graph (SSA form): an atom (predicate + args) or a
// connective whose `children` are integer indices into the judgment's node list.
interface Node {
  kind: string
  predicate: string
  args: Arg[]
  children: number[]
}

interface Judgment {
  status: string
  term: string
  type: number
  context: { var: string; type: number }[]
  nodes: Node[]
}

interface Classification {
  category: string
  tags: string[]
  propositions: Proposition[]
  judgment: Judgment | null
}

async function classify(text: string, apiKey: string): Promise<Classification> {
  // DigitalOcean is OpenAI-compatible; we ask for a JSON object and parse it.
  // There's no server-side schema enforcement here, so the prompt spells out the
  // exact shape and the normalize*() helpers below defensively coerce the result.
  const res = await fetch(DO_CHAT_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: CHAT_MODEL,
      max_tokens: 3072,
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'system',
          content:
        'You analyze short personal notes. Do four things:\n' +
        '1. category: choose the single best-fitting category.\n' +
        '2. tags: 1-5 concise lowercase topic tags describing the note.\n' +
        '3. propositions: extract every assertion the note makes - each ' +
        "statement that could be true or false (a claim, not a question or " +
        'command). Represent each as a predicate applied to its arguments:\n' +
        '   - predicate: the asserted property or relation, lowercased to its ' +
        "base form (e.g. 'is blue' -> blue, 'loves' -> loves, 'is in' -> in).\n" +
        '   - args: the entities the predicate is about, in order. For each ' +
        'arg give the entity as a lowercase noun phrase (hyphenate multi-word ' +
        "entities, e.g. big-dog) and its surface article: 'a', 'an', 'the', or " +
        "'none'. Use 'none' for proper nouns, pronouns, plurals and mass nouns " +
        'that carry no article.\n' +
        '   Preserve the article exactly as used: "the dog is blue" -> ' +
        'predicate blue, args [{entity:dog, article:the}]; "a dog is blue" -> ' +
        'predicate blue, args [{entity:dog, article:a}]; "John loves Mary" -> ' +
        'predicate loves, args [{entity:john, article:none},{entity:mary, ' +
        'article:none}]. The article matters: the-dog and a-dog are different ' +
        'entities. If the note makes no assertions, return an empty list.\n' +
        '4. judgment: a Curry-Howard reading of the note as a whole, where the ' +
        "note's logical content is a TYPE and the note is a proof TERM:\n" +
        '   - status: the inhabitation status / mood. "proved" = the note ' +
        'asserts the type is true (the note is its witness; set term to "note"). ' +
        '"goal" = the note asks/wonders whether the type holds (no witness; set ' +
        'term to "?"). "hypothetical" = the note supposes it ("if/suppose..."). ' +
        '"refuted" = the note denies it (set term to "note").\n' +
        '   - type: the index (into nodes) of the root of the type expression.\n' +
        '   - nodes: a flat list encoding the type as a graph. Each node is ' +
        'either an atom or a connective:\n' +
        '       atom: kind="atom", predicate+args exactly like a proposition ' +
        'above, children=[].\n' +
        '       connective: kind is "arrow" (implication P->Q, children=[P,Q]), ' +
        '"prod" (conjunction P and Q, children=[P,Q,...]), "sum" (disjunction P ' +
        'or Q, children=[P,Q,...]), or "neg" (negation not P, children=[P]); ' +
        'predicate="" and args=[] for connectives. children are integer indices ' +
        'into nodes.\n' +
        '   - context: hypotheses (each {var, type:<node index>}); usually [], ' +
        'use it only when the note explicitly assumes something.\n' +
        '   Examples. "The fridge is empty." -> status proved, term "note", a ' +
        'single atom node, type pointing at it. "If the fridge is empty, buy ' +
        'milk." -> nodes [atom(empty,the-fridge), atom(buy,milk), ' +
        'arrow children [0,1]], type 2, status proved. "Is a conclusion ' +
        'drawable?" -> one atom, status goal, term "?". Keep the judgment a ' +
        'faithful single type for the whole note; if the note has no assertible ' +
        'content, use a single atom and status goal.\n\n' +
        'Respond with ONLY a single JSON object - no markdown, no code fences, ' +
        'no prose - with exactly these keys:\n' +
        '  category: one of ' + CATEGORIES.join(', ') + '\n' +
        '  tags: array of 1-5 lowercase strings\n' +
        '  propositions: array of {"predicate": string, "args": [{"entity": ' +
        'string, "article": one of ' + ARTICLES.join('/') + '}]}\n' +
        '  judgment: {"status": one of ' + STATUSES.join('/') + ', "term": ' +
        'string, "type": integer (root node index), "context": [{"var": string, ' +
        '"type": integer}], "nodes": [{"kind": one of ' + KINDS.join('/') + ', ' +
        '"predicate": string, "args": [{"entity": string, "article": ...}], ' +
        '"children": [integer]}]}\n' +
        'Use [] for empty arrays.',
        },
        { role: 'user', content: text },
      ],
    }),
  })
  if (!res.ok) {
    throw new Error(`digitalocean inference error ${res.status}: ${await res.text()}`)
  }
  const json = await res.json()
  const content = json?.choices?.[0]?.message?.content
  if (typeof content !== 'string' || content.trim().length === 0) {
    throw new Error('digitalocean inference returned no content')
  }
  const parsed = JSON.parse(stripJsonFences(content)) as Classification
  const category = (CATEGORIES as readonly string[]).includes(parsed.category)
    ? parsed.category
    : 'other'
  const tags = Array.isArray(parsed.tags)
    ? parsed.tags.map((t) => String(t)).slice(0, 5)
    : []
  const propositions = normalizePropositions(parsed.propositions)
  const judgment = normalizeJudgment(parsed.judgment)
  return { category, tags, propositions, judgment }
}

// Chat models sometimes wrap JSON in ```json fences despite instructions.
function stripJsonFences(s: string): string {
  const t = s.trim()
  const fenced = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i)
  return (fenced ? fenced[1] : t).trim()
}

function normalizeArg(raw: unknown): Arg | null {
  const entity = String((raw as Arg)?.entity ?? '').trim()
  if (!entity) return null
  const article = (ARTICLES as readonly string[]).includes((raw as Arg)?.article)
    ? (raw as Arg).article
    : 'none'
  return { entity, article }
}

// Validate the term-graph judgment: well-formed nodes, an in-range root, and
// child/context indices that actually point at nodes. Return null on anything
// malformed so we simply store no judgment rather than a broken one.
function normalizeJudgment(raw: unknown): Judgment | null {
  if (!raw || typeof raw !== 'object') return null
  const j = raw as Judgment
  if (!Array.isArray(j.nodes) || j.nodes.length === 0) return null

  const nodes: Node[] = []
  for (const n of j.nodes) {
    const kind = (KINDS as readonly string[]).includes((n as Node)?.kind)
      ? (n as Node).kind
      : 'atom'
    const predicate = String((n as Node)?.predicate ?? '').trim()
    const args = Array.isArray((n as Node)?.args)
      ? ((n as Node).args.map(normalizeArg).filter(Boolean) as Arg[])
      : []
    const children = Array.isArray((n as Node)?.children)
      ? (n as Node).children
          .map((c) => Number(c))
          .filter((c) => Number.isInteger(c))
      : []
    nodes.push({ kind, predicate, args, children })
  }
  const inRange = (i: number) => Number.isInteger(i) && i >= 0 && i < nodes.length
  // Every child reference must resolve to a real node.
  for (const n of nodes) {
    if (!n.children.every(inRange)) return null
  }
  const type = Number(j.type)
  if (!inRange(type)) return null

  const status = (STATUSES as readonly string[]).includes(j.status)
    ? j.status
    : 'proved'
  const term = String(j.term ?? '').trim() || (status === 'goal' ? '?' : 'note')
  const context = Array.isArray(j.context)
    ? j.context
        .map((h) => ({ var: String(h?.var ?? '').trim(), type: Number(h?.type) }))
        .filter((h) => h.var && inRange(h.type))
    : []

  return { status, term, type, context, nodes }
}

// Defensively coerce the model's propositions into well-formed objects, dropping
// anything without a predicate and at least one valid arg.
function normalizePropositions(raw: unknown): Proposition[] {
  if (!Array.isArray(raw)) return []
  const out: Proposition[] = []
  for (const item of raw) {
    const predicate = String((item as Proposition)?.predicate ?? '').trim()
    const rawArgs = (item as Proposition)?.args
    if (!predicate || !Array.isArray(rawArgs)) continue
    const args = rawArgs.map(normalizeArg).filter(Boolean) as Arg[]
    if (args.length === 0) continue
    out.push({ predicate, args })
  }
  return out
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('expected POST request', { status: 405 })
  }

  let id: string | undefined
  try {
    ;({ id } = await req.json())
  } catch {
    return new Response('expected json body', { status: 400 })
  }
  if (!id) {
    return new Response('missing id', { status: 400 })
  }

  try {
    const [row] = await sql`
      select coalesce(title, '') || E'\n\n' || coalesce(content, '') as content
      from public.notes
      where id = ${id}
    `
    if (!row) {
      return new Response(`note not found: ${id}`, { status: 404 })
    }

    const text = (row.content as string).trim()

    // Nothing to classify - clear any stale classification.
    if (text.length === 0) {
      await sql`update public.notes set category = null, tags = null, propositions = null, judgment = null where id = ${id}`
      return new Response(JSON.stringify({ id, classified: false }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    // The DigitalOcean inference key lives in Supabase Vault (shared with embed).
    const [secret] = await sql`
      select decrypted_secret from vault.decrypted_secrets where name = 'digitalocean-inference-model-key'
    `
    if (!secret?.decrypted_secret) {
      throw new Error('digitalocean-inference-model-key not found in vault')
    }

    const { category, tags, propositions, judgment } = await classify(
      text,
      secret.decrypted_secret as string,
    )
    await sql`
      update public.notes
      set category = ${category}, tags = ${tags},
          propositions = ${sql.json(propositions)}, judgment = ${judgment ? sql.json(judgment) : null}
      where id = ${id}
    `

    return new Response(
      JSON.stringify({ id, classified: true, category, tags, propositions, judgment }),
      {
        status: 200,
        headers: { 'content-type': 'application/json' },
      },
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('classify failed', { id, message })
    return new Response(JSON.stringify({ id, error: message }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    })
  }
})
