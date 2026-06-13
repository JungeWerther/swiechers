// Classifies a single note row with Claude Haiku and writes category, tags +
// propositions back. Invoked asynchronously by a Postgres trigger via pg_net on
// insert/update.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

// Cheap, fast model for short-text classification.
const ANTHROPIC_MODEL = 'claude-haiku-4-5'
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

interface Classification {
  category: string
  tags: string[]
  propositions: Proposition[]
}

async function classify(text: string, apiKey: string): Promise<Classification> {
  // Structured outputs (output_config.format) constrain the response to the
  // schema, so we always get back valid JSON matching {category, tags, propositions}.
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 2048,
      system:
        'You analyze short personal notes. Do three things:\n' +
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
        'entities. If the note makes no assertions, return an empty list.',
      messages: [{ role: 'user', content: text }],
      output_config: {
        format: {
          type: 'json_schema',
          schema: {
            type: 'object',
            properties: {
              category: { type: 'string', enum: CATEGORIES },
              tags: { type: 'array', items: { type: 'string' } },
              propositions: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    predicate: { type: 'string' },
                    args: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          entity: { type: 'string' },
                          article: { type: 'string', enum: ARTICLES },
                        },
                        required: ['entity', 'article'],
                        additionalProperties: false,
                      },
                    },
                  },
                  required: ['predicate', 'args'],
                  additionalProperties: false,
                },
              },
            },
            required: ['category', 'tags', 'propositions'],
            additionalProperties: false,
          },
        },
      },
    }),
  })
  if (!res.ok) {
    throw new Error(`anthropic api error ${res.status}: ${await res.text()}`)
  }
  const json = await res.json()
  const block = json?.content?.find((b: { type: string }) => b.type === 'text')
  if (!block?.text) {
    throw new Error('anthropic api returned no text content')
  }
  const parsed = JSON.parse(block.text) as Classification
  const category = (CATEGORIES as readonly string[]).includes(parsed.category)
    ? parsed.category
    : 'other'
  const tags = Array.isArray(parsed.tags)
    ? parsed.tags.map((t) => String(t)).slice(0, 5)
    : []
  const propositions = normalizePropositions(parsed.propositions)
  return { category, tags, propositions }
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
    const args: Arg[] = []
    for (const a of rawArgs) {
      const entity = String((a as Arg)?.entity ?? '').trim()
      if (!entity) continue
      const article = (ARTICLES as readonly string[]).includes((a as Arg)?.article)
        ? (a as Arg).article
        : 'none'
      args.push({ entity, article })
    }
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
      await sql`update public.notes set category = null, tags = null, propositions = null where id = ${id}`
      return new Response(JSON.stringify({ id, classified: false }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    // The Anthropic key lives in Supabase Vault (added via the dashboard).
    const [secret] = await sql`
      select decrypted_secret from vault.decrypted_secrets where name = 'anthropic-key'
    `
    if (!secret?.decrypted_secret) {
      throw new Error('anthropic-key not found in vault')
    }

    const { category, tags, propositions } = await classify(
      text,
      secret.decrypted_secret as string,
    )
    await sql`
      update public.notes
      set category = ${category}, tags = ${tags}, propositions = ${sql.json(propositions)}
      where id = ${id}
    `

    return new Response(
      JSON.stringify({ id, classified: true, category, tags, propositions }),
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
