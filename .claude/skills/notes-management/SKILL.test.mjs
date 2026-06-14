// Tests that parse the notes-management SKILL.md and assert it stays in sync
// with the live `notes` pipeline (schema columns, models, Vault secrets).
//
// No test framework is configured in this repo, so this uses Node's built-in
// runner (node >= 18). Run it with:
//
//   node --test .claude/skills/notes-management/SKILL.test.mjs
//
// These tests are deliberately structural: they check that the documented
// facts are present and the markdown tables are well-formed, not that the prose
// is worded a particular way — so ordinary doc edits don't break them, but
// dropping a column or silently changing a model does.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const md = readFileSync(join(here, 'SKILL.md'), 'utf8')

// --- tiny markdown helpers -------------------------------------------------

// Split the leading `---` ... `---` YAML frontmatter from the body.
function parseFrontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/)
  assert.ok(m, 'SKILL.md must start with a --- frontmatter block')
  const fields = {}
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/)
    if (kv) fields[kv[1]] = kv[2].trim()
  }
  return { fields, body: m[2] }
}

// Return the body of the section started by the given heading (e.g. "## Schema"
// or "### embed"), up to the next heading of the same-or-higher level. The match
// is by prefix, so "### embed" finds "### embed → `embedding`".
function section(text, heading) {
  const level = heading.match(/^#+/)[0].length
  const lines = text.split('\n')
  const start = lines.findIndex(
    (l) => l.trim() === heading || l.trim().startsWith(heading + ' '),
  )
  assert.notEqual(start, -1, `expected a "${heading}" heading`)
  const out = []
  for (let i = start + 1; i < lines.length; i++) {
    const h = lines[i].match(/^(#+)\s/)
    if (h && h[1].length <= level) break
    out.push(lines[i])
  }
  return out.join('\n')
}

// Parse every GitHub-flavoured markdown table in `text` into
// { header: string[], rows: string[][] }, splitting cells on unescaped pipes.
function parseTables(text) {
  const lines = text.split('\n')
  const tables = []
  for (let i = 0; i < lines.length; i++) {
    if (!/^\s*\|.*\|\s*$/.test(lines[i])) continue
    // A header row must be followed by a |---|---| separator row.
    if (!/^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1] ?? '')) continue
    const cells = (row) =>
      row.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim())
    const header = cells(lines[i])
    const rows = []
    let j = i + 2
    for (; j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j]); j++) {
      rows.push(cells(lines[j]))
    }
    tables.push({ header, rows })
    i = j - 1
  }
  return tables
}

// Pull every `backtick token` out of a string.
function codeTokens(s) {
  return [...s.matchAll(/`([^`]+)`/g)].map((m) => m[1])
}

const { fields, body } = parseFrontmatter(md)

// --- frontmatter -----------------------------------------------------------

test('frontmatter declares the skill name and a description', () => {
  assert.equal(fields.name, 'notes-management')
  assert.ok(
    fields.description && fields.description.length > 20,
    'description should be a non-trivial sentence',
  )
})

// --- schema table ----------------------------------------------------------

test('schema table documents every notes column', () => {
  const schema = section(body, '## Schema')
  const tables = parseTables(schema)
  assert.ok(tables.length >= 1, 'Schema section must contain a table')
  const table = tables[0]
  assert.deepEqual(
    table.header.map((h) => h.toLowerCase()),
    ['column', 'type', 'notes'],
    'schema table header should be Column | Type | Notes',
  )

  // Collect column names from the first cell of every row. A single cell may
  // list more than one column (e.g. `created_at` / `updated_at`), so pull every
  // backtick token rather than reading the cell verbatim.
  const documented = new Set()
  for (const row of table.rows) {
    for (const tok of codeTokens(row[0])) documented.add(tok)
  }

  const expected = [
    'id',
    'user_id',
    'title',
    'content',
    'created_at',
    'updated_at',
    'category',
    'tags',
    'propositions',
    'propositions_sexpr',
    'judgment',
    'judgment_sexpr',
    'embedding',
  ]
  for (const col of expected) {
    assert.ok(documented.has(col), `schema table is missing column: ${col}`)
  }
})

test('generated s-expr columns are documented as generated/read-only', () => {
  const schema = section(body, '## Schema')
  const table = parseTables(schema)[0]
  for (const col of ['propositions_sexpr', 'judgment_sexpr']) {
    const row = table.rows.find((r) => codeTokens(r[0]).includes(col))
    assert.ok(row, `no schema row for ${col}`)
    assert.match(
      row[2].toLowerCase(),
      /generated/,
      `${col} should be described as generated`,
    )
  }
})

// --- classify pipeline -----------------------------------------------------

test('classify section names the current model and its four outputs', () => {
  const classify = section(body, '### classify')
  assert.match(classify, /glm-5/, 'classify should document the glm-5 model')
  assert.match(
    classify,
    /digitalocean-inference-model-key/,
    'classify should read its key from the DigitalOcean Vault secret',
  )
  for (const out of ['category', 'tags', 'propositions', 'judgment']) {
    assert.match(
      classify,
      new RegExp(`\\b${out}\\b`),
      `classify should document the ${out} output`,
    )
  }
})

// --- embed pipeline --------------------------------------------------------

test('embed section names the embedding model and dimensionality', () => {
  const embed = section(body, '### embed')
  assert.match(embed, /qwen3-embedding-0\.6b/, 'embed should name the qwen3 model')
  assert.match(embed, /vector\(1024\)|1024/, 'embed should state the 1024-dim size')
})

// --- vault secrets ---------------------------------------------------------

test('vault secrets table lists the secrets the functions read', () => {
  const vault = section(body, '## Vault secrets used')
  const table = parseTables(vault)[0]
  assert.ok(table, 'Vault section must contain a table')
  const secrets = new Set()
  for (const row of table.rows) {
    for (const tok of codeTokens(row[0])) secrets.add(tok)
  }
  for (const s of ['project_url', 'anon_key', 'digitalocean-inference-model-key']) {
    assert.ok(secrets.has(s), `Vault table is missing secret: ${s}`)
  }
})

// --- structural integrity --------------------------------------------------

test('every markdown table is well-formed (consistent column count)', () => {
  for (const { header, rows } of parseTables(body)) {
    for (const row of rows) {
      assert.equal(
        row.length,
        header.length,
        `table row has ${row.length} cells, header has ${header.length}: ${row.join(' | ')}`,
      )
    }
  }
})
