#!/usr/bin/env node
/**
 * Transforma o catálogo de cartas (supabase/cards/cards.json) em SQL.
 *
 *   node scripts/build-cards.mjs
 *
 * Gera supabase/cards/02_cards_seed.sql -> cole no Supabase (SQL Editor) e rode.
 * Pode rodar quantas vezes quiser: cartas novas entram, cartas existentes são atualizadas
 * (ninguém perde as cartas que já ganhou).
 *
 * Para ADICIONAR uma carta:
 *   1) salve a imagem em  public/cards/<id>.webp   (ou .png)   — fundo transparente, ~420x640
 *   2) acrescente uma linha em  supabase/cards/cards.json
 *   3) rode este script e depois o SQL gerado
 * Campos: id, name, tier (basica|destaque|lenda|epica), overall            <- obrigatórios
 *         position, club (id do clube no jogo), player, weight (padrão 100), image (padrão "<id>.webp"),
 *         active (false = para de cair), meta ({...})                        <- opcionais
 *
 * Para TIRAR uma carta de circulação sem apagar: "active": false.
 * Para deixá-la mais rara dentro da sua raridade: diminua "weight" (ex.: 20 contra 100).
 */
import { readFile, writeFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const JSON_FILE = path.join(ROOT, 'supabase', 'cards', 'cards.json')
const SQL_FILE = path.join(ROOT, 'supabase', 'cards', '02_cards_seed.sql')
const IMG_DIR = path.join(ROOT, 'public', 'cards')
const TIERS = ['basica', 'destaque', 'lenda', 'epica']

const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
const fail = (msg) => {
  console.error(`✖ ${msg}`)
  process.exitCode = 1
}

const cards = JSON.parse(await readFile(JSON_FILE, 'utf8'))
if (!Array.isArray(cards)) throw new Error('cards.json precisa ser uma lista [ ... ]')
const files = new Set(await readdir(IMG_DIR).catch(() => []))
const seen = new Set()
const rows = []

for (const [i, c] of cards.entries()) {
  const at = `carta #${i + 1} (${c.id ?? 'sem id'})`
  if (!c.id || !/^[a-z0-9-]+$/.test(c.id)) { fail(`${at}: "id" obrigatório, só letras minúsculas, números e "-"`); continue }
  if (seen.has(c.id)) { fail(`${at}: id repetido`); continue }
  seen.add(c.id)
  if (!c.name) { fail(`${at}: falta "name"`); continue }
  if (!TIERS.includes(c.tier)) { fail(`${at}: "tier" deve ser ${TIERS.join(' | ')}`); continue }
  if (!Number.isInteger(c.overall) || c.overall < 1 || c.overall > 130) { fail(`${at}: "overall" deve ser um número inteiro (1 a 130)`); continue }
  const image = c.image || `${c.id}.webp`
  if (!files.has(image)) console.warn(`⚠ ${at}: imagem public/cards/${image} não encontrada (a carta vai aparecer sem figura)`)
  const weight = c.weight ?? 100
  if (!Number.isInteger(weight) || weight < 1) { fail(`${at}: "weight" deve ser inteiro >= 1`); continue }
  rows.push(
    `  (${q(c.id)}, ${q(c.name)}, ${q(c.tier)}, ${c.overall}, ${q(c.position)}, ${q(c.club)}, ${q(c.player)}, ${q(image)}, ${weight}, ${c.active === false ? 'false' : 'true'}, ${q(JSON.stringify(c.meta ?? {}))}::jsonb)`,
  )
}

const used = new Set(cards.map((c) => c.image || `${c.id}.webp`))
const orphan = [...files].filter((f) => !used.has(f))
if (orphan.length) console.warn(`ℹ imagens em public/cards sem carta no JSON: ${orphan.join(', ')}`)

if (!process.exitCode && rows.length === 0) {
  await writeFile(SQL_FILE, '-- GERADO por scripts/build-cards.mjs: nenhuma carta manual em supabase/cards/cards.json.\n-- As cartas do jogo são geradas por scripts/build-auto-cards.mjs (03_auto_cards.sql).\n')
  console.log('✔ nenhuma carta manual (as automáticas ficam em 03_auto_cards.sql)')
} else if (process.exitCode) {
  console.error('Nada foi gerado. Corrija os erros acima.')
} else {
  const sql = `-- GERADO por scripts/build-cards.mjs a partir de supabase/cards/cards.json — não edite à mão.
-- Rode no Supabase (SQL Editor) sempre que mudar o catálogo.
insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta) values
${rows.join(',\n')}
on conflict (id) do update set
  name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image,
  weight = excluded.weight, active = excluded.active, meta = excluded.meta;
`
  await writeFile(SQL_FILE, sql)
  const byTier = TIERS.map((t) => `${t}: ${cards.filter((c) => c.tier === t).length}`).join(' · ')
  console.log(`✔ ${rows.length} cartas -> ${path.relative(ROOT, SQL_FILE)}  (${byTier})`)
}
