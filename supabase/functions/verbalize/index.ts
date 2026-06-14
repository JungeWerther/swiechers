// Fluent verbalizer: turns a logic s-expression (and an optional rough gloss)
// into one natural English sentence via the DigitalOcean chat model. The fluent
// counterpart to the deterministic verbalize_* SQL functions - call this when a
// program has produced a structure and you want readable prose back out.
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

const CHAT_MODEL = 'llama3.3-70b-instruct'
const DO_CHAT_URL = 'https://inference.do-ai.run/v1/chat/completions'
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!)

const SYSTEM =
  'You translate a small logic notation into one natural English sentence.\n' +
  '- (predicate args...) applies a predicate to its arguments.\n' +
  '- Tokens like the-dog / a-dog keep their article (definite vs indefinite) - ' +
  'preserve it; a bare token (john, milk) has no article.\n' +
  '- Connectives: (-> A B) = "if A then B"; (* A B ...) = "A and B"; ' +
  '(+ A B ...) = "A or B"; (not A) = negation.\n' +
  '- Mood wrappers: (proved <term> T) asserts T (write a statement); ' +
  '(goal ? T) questions T (write a QUESTION ending in "?"); ' +
  '(refuted <term> T) denies T; (|- (ctx) J) = "given ctx, J".\n' +
  'Write exactly ONE fluent, natural sentence conveying the structure, ' +
  'preserving the mood and the articles. Output only the sentence.'

async function verbalize(sexpr: string, gloss: string, apiKey: string): Promise<string> {
  const user = gloss ? `s-expression: ${sexpr}\nrough gloss: ${gloss}` : `s-expression: ${sexpr}`
  const res = await fetch(DO_CHAT_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model: CHAT_MODEL,
      max_tokens: 256,
      temperature: 0.3,
      messages: [
        { role: 'system', content: SYSTEM },
        { role: 'user', content: user },
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
  return content.trim().replace(/^["']|["']$/g, '')
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('expected POST request', { status: 405 })
  }

  let body: { sexpr?: string; gloss?: string }
  try {
    body = await req.json()
  } catch {
    return new Response('expected json body', { status: 400 })
  }
  const sexpr = (body.sexpr ?? '').trim()
  if (!sexpr) {
    return new Response('missing sexpr', { status: 400 })
  }

  try {
    const [secret] = await sql`
      select decrypted_secret from vault.decrypted_secrets where name = 'digitalocean-inference-model-key'
    `
    if (!secret?.decrypted_secret) {
      throw new Error('digitalocean-inference-model-key not found in vault')
    }
    const sentence = await verbalize(sexpr, (body.gloss ?? '').trim(), secret.decrypted_secret as string)
    return new Response(JSON.stringify({ sexpr, sentence }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error('verbalize failed', { message })
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    })
  }
})
