// Classifies a single note row with Claude Haiku and writes category + tags back.
// Invoked asynchronously by a Postgres trigger via pg_net on insert/update.
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

// Built-in env var: full-access connection string for this project's database.
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!)

interface Classification {
  category: string
  tags: string[]
}

async function classify(text: string, apiKey: string): Promise<Classification> {
  // Structured outputs (output_config.format) constrain the response to the
  // schema, so we always get back valid JSON matching {category, tags}.
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 1024,
      system:
        'You classify short personal notes. Choose the single best-fitting ' +
        'category and 1-5 concise lowercase topic tags that describe the note.',
      messages: [{ role: 'user', content: text }],
      output_config: {
        format: {
          type: 'json_schema',
          schema: {
            type: 'object',
            properties: {
              category: { type: 'string', enum: CATEGORIES },
              tags: { type: 'array', items: { type: 'string' } },
            },
            required: ['category', 'tags'],
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
  return { category, tags }
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
      await sql`update public.notes set category = null, tags = null where id = ${id}`
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

    const { category, tags } = await classify(text, secret.decrypted_secret as string)
    await sql`
      update public.notes set category = ${category}, tags = ${tags} where id = ${id}
    `

    return new Response(JSON.stringify({ id, classified: true, category, tags }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('classify failed', { id, message })
    return new Response(JSON.stringify({ id, error: message }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    })
  }
})
