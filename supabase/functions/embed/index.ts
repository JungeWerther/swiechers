// Generates an embedding for a single note row and writes it back.
// Invoked asynchronously by a Postgres trigger via pg_net on insert/update.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

// DigitalOcean Gradient serverless inference (OpenAI-compatible embeddings).
// qwen3-embedding-0.6b returns 1024-dim vectors, matching notes.embedding.
const EMBEDDING_MODEL = 'qwen3-embedding-0.6b'
const DO_INFERENCE_URL = 'https://inference.do-ai.run/v1/embeddings'

// Built-in env var: full-access connection string for this project's database.
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!)

async function generateEmbedding(text: string, apiKey: string): Promise<number[]> {
  const res = await fetch(DO_INFERENCE_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model: EMBEDDING_MODEL, input: text }),
  })
  if (!res.ok) {
    throw new Error(`digitalocean inference error ${res.status}: ${await res.text()}`)
  }
  const json = await res.json()
  const embedding = json?.data?.[0]?.embedding
  if (!Array.isArray(embedding)) {
    throw new Error('digitalocean inference returned no embedding')
  }
  return embedding
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
      select id, coalesce(title, '') || E'\n\n' || coalesce(content, '') as content
      from public.notes
      where id = ${id}
    `
    if (!row) {
      return new Response(`note not found: ${id}`, { status: 404 })
    }

    const text = (row.content as string).trim()

    // Nothing to embed - clear any stale embedding.
    if (text.length === 0) {
      await sql`update public.notes set embedding = null where id = ${id}`
      return new Response(JSON.stringify({ id, embedded: false }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    }

    // The DigitalOcean inference key lives in Supabase Vault.
    const [secret] = await sql`
      select decrypted_secret from vault.decrypted_secrets where name = 'digitalocean-inference-model-key'
    `
    if (!secret?.decrypted_secret) {
      throw new Error('digitalocean-inference-model-key not found in vault')
    }

    const embedding = await generateEmbedding(text, secret.decrypted_secret as string)
    await sql`
      update public.notes
      set embedding = ${JSON.stringify(embedding)}
      where id = ${id}
    `

    return new Response(JSON.stringify({ id, embedded: true, dims: embedding.length }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('embed failed', { id, message })
    return new Response(JSON.stringify({ id, error: message }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    })
  }
})
