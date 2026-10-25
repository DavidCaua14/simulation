#!/usr/bin/env node
/**
 * Gera os DADOS DE REFERÊNCIA das competições (clubes novos, competições, participantes, potes, acesso/rebaixamento)
 *
 *   node scripts/build-competitions.mjs
 *
 * Entradas (versionadas):
 *   data/clubs/clubs_evolution.json          -> clubes novos (dados oficiais usados para estimar a força em "basis")
 *   data/competitions/competitions.json      -> formato, fases, desempates, objetivos, participantes, acesso/rebaixamento
 *   data/competitions/ucl_swiss_templates.json -> modelos do calendário da fase de liga da UCL (scripts/gen-swiss-template.py)
 * Saídas:
 *   supabase/evolution/02_reference_data.sql -> seed IDEMPOTENTE (pode rodar quantas vezes quiser)
 *   data/clubs/generated_strength.json       -> força calculada (lida por scripts/build-squads.mjs)
 *
 * FORÇA (strength, 30–99) = ESTIMATIVA DE GAMEPLAY a partir de um dado oficial (nada é inventado):
 *   pl_prev_pos       posição na Premier League 2025/26:       88 - (pos-1)*0.6
 *   champ_prev_pos    posição na Championship 2025/26:          76 - (pos-1)*0.5
 *   l1_promoted       promovido da League One 2025/26:          65
 *   uefa_coef         coeficiente de clube da UEFA (potes 2026/27): 62 + 26*sqrt(coef/150)
 *   seriea_relegated  rebaixado da Série A 2025 (17º a 20º):    65 - (pos-17)
 *   serieb_prev_pos   posição na Série B 2025 (5º a 16º):       63 - (pos-5)*0.55
 *   seriec_promoted   promovido da Série C 2025:                56
 * Clubes que já existiam (Série A, Libertadores, Fortaleza, Juventude) mantêm a força cadastrada.
 */
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const P = (...p) => path.join(ROOT, ...p)

export function strengthOf(b) {
  const r = Math.round
  switch (b.type) {
    case 'pl_prev_pos': return r(88 - (b.pos - 1) * 0.6)
    case 'champ_prev_pos': return r(76 - (b.pos - 1) * 0.5)
    case 'l1_promoted': return 65
    case 'uefa_coef': return Math.min(89, r(62 + 26 * Math.sqrt(b.value / 150)))
    case 'seriea_relegated': return r(65 - (b.pos - 17))
    case 'serieb_prev_pos': return r(63 - (b.pos - 5) * 0.55)
    case 'seriec_promoted': return 56
    default: throw new Error(`base de força desconhecida: ${b.type}`)
  }
}

const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
const j = (v) => `${q(JSON.stringify(v))}::jsonb`

async function main() {
  const clubsJson = JSON.parse(await readFile(P('data/clubs/clubs_evolution.json'), 'utf8'))
  const comps = JSON.parse(await readFile(P('data/competitions/competitions.json'), 'utf8'))
  const tpl = JSON.parse(await readFile(P('data/competitions/ucl_swiss_templates.json'), 'utf8'))
  const oldSeed = await readFile(P('supabase/seasons/02_seed.sql'), 'utf8')
  const oldIds = new Set([...oldSeed.matchAll(/^\('([a-z0-9-]+)',/gm)].map((m) => m[1]))

  const clubs = clubsJson.clubs.map(([id, name, short, country, region, tier, c1, c2, article, full, city, basis]) => ({
    id, name, short, country, region, tier, c1, c2, article, full, city, basis, strength: strengthOf(basis),
  }))
  const known = new Set([...oldIds, ...clubs.map((c) => c.id)])
  for (const c of clubs) if (oldIds.has(c.id)) throw new Error(`${c.id} já existe em 02_seed.sql`)

  // --- validações dos participantes (nada de clube inexistente / repetido / quantidade errada)
  const part = comps.participants
  const check = (label, list, n) => {
    if (list.length !== n) throw new Error(`${label}: ${list.length} clubes (esperado ${n})`)
    const dup = list.filter((x, i) => list.indexOf(x) !== i)
    if (dup.length) throw new Error(`${label}: repetidos ${dup}`)
    for (const id of list) if (!known.has(id)) throw new Error(`${label}: clube desconhecido ${id}`)
  }
  check('serie_b', part.serie_b, 20)
  check('premier_league', part.premier_league, 20)
  check('championship', part.championship, 24)
  const ucl = Object.entries(part.ucl_pots).flatMap(([pot, ids]) => ids.map((id) => ({ id, pot: Number(pot) })))
  check('ucl', ucl.map((x) => x.id), 36)
  for (const ids of Object.values(part.ucl_pots)) if (ids.length !== 9) throw new Error('pote da UCL sem 9 clubes')
  const both = part.premier_league.filter((x) => part.championship.includes(x))
  if (both.length) throw new Error(`clube em duas divisões: ${both}`)

  // copas inglesas: as fases de entrada precisam fechar a conta (vencedores + novos = potência de 2)
  for (const id of ['fa_cup', 'efl_cup']) {
    const c = comps.competitions.find((x) => x.id === id)
    const entry = c.rules.entry
    const phases = c.rules.phases.map((p) => p.id)
    let alive = 0
    for (const ph of phases) {
      alive += (entry.premier_league === ph ? 20 : 0) + (entry.championship === ph ? 24 : 0)
      if (alive % 2) throw new Error(`${id}: número ímpar de clubes na fase ${ph}`)
      alive /= 2
    }
    if (alive !== 1) throw new Error(`${id}: a chave não termina com 1 campeão (${alive})`)
  }

  let sql = `-- =====================================================================
-- EVOLUÇÃO 02 — DADOS DE REFERÊNCIA (gerado por scripts/build-competitions.mjs — NÃO edite à mão)
-- Fontes: data/clubs/clubs_evolution.json e data/competitions/competitions.json (cada competição lista as fontes oficiais)
-- Temporadas de referência: Brasil 2026 · Inglaterra/Europa 2026/27. Idempotente.
-- =====================================================================
begin;

-- 1) clubes novos (força = estimativa a partir de dado oficial; ver o cabeçalho do script)
insert into public.sim_clubs (id, name, short_name, country, tier, strength, color_primary, color_secondary, region, article, full_name, city) values
${clubs.map((c) => `(${[q(c.id), q(c.name), q(c.short), q(c.country), q(c.tier), c.strength, q(c.c1), q(c.c2), q(c.region), q(c.article), q(c.full), q(c.city)].join(', ')})`).join(',\n')}
on conflict (id) do update set name = excluded.name, short_name = excluded.short_name, country = excluded.country, tier = excluded.tier,
  strength = excluded.strength, color_primary = excluded.color_primary, color_secondary = excluded.color_secondary,
  region = excluded.region, article = excluded.article, full_name = excluded.full_name, city = excluded.city;

-- clubes que já existiam: região e divisão de referência
update public.sim_clubs set region = 'BRA' where country = 'BRA';
update public.sim_clubs set tier = 'serie_b' where id in ('fortaleza', 'juventude');

-- 2) competições
`
  for (const c of comps.competitions) {
    const rules = { ...c.rules }
    if (c.id === 'ucl') rules.swiss_templates = tpl.templates
    sql += `insert into public.sim_competitions (id, name, short_name, sort_order, xp_mult, rules, region, kind, division, ref_season, sources, theme, active)
values (${[q(c.id), q(c.name), q(c.short_name), c.sort_order, c.xp_mult, j(rules), q(c.region), q(c.kind), c.division ?? 'null', q(c.ref_season), j(c.sources), j(c.theme), 'true'].join(', ')})
on conflict (id) do update set name = excluded.name, short_name = excluded.short_name, sort_order = excluded.sort_order, xp_mult = excluded.xp_mult,
  rules = excluded.rules, region = excluded.region, kind = excluded.kind, division = excluded.division, ref_season = excluded.ref_season,
  sources = excluded.sources, theme = excluded.theme, active = true;
`
  }

  // 3) participantes de referência
  const rows = []
  for (const id of part.serie_b) rows.push(['serie_b', id, null, null, null])
  for (const id of part.premier_league) rows.push(['premier_league', id, null, null, null])
  for (const id of part.championship) rows.push(['championship', id, null, null, null])
  for (const cup of ['fa_cup', 'efl_cup']) {
    const entry = comps.competitions.find((x) => x.id === cup).rules.entry
    for (const id of part.premier_league) rows.push([cup, id, null, null, entry.premier_league])
    for (const id of part.championship) rows.push([cup, id, null, null, entry.championship])
  }
  for (const x of ucl) rows.push(['ucl', x.id, null, x.pot, null])
  sql += `
-- 3) participantes da temporada de referência (as temporadas seguintes de cada carreira mudam com acesso/rebaixamento)
delete from public.sim_competition_clubs where competition_id in ('serie_b', 'premier_league', 'championship', 'fa_cup', 'efl_cup', 'ucl');
insert into public.sim_competition_clubs (competition_id, club_id, group_label, seed, entry_phase) values
${rows.map((r) => `(${q(r[0])}, ${q(r[1])}, ${q(r[2])}, ${r[3] ?? 'null'}, ${q(r[4])})`).join(',\n')};
-- Fortaleza e Juventude disputam a Série B 2026 (e seguem na Copa do Brasil de referência)

-- 4) acesso e rebaixamento
`
  for (const p of comps.promotion) {
    const id = `${p.region}:${p.upper}>${p.lower}`
    sql += `insert into public.sim_promotion_rules (id, region, upper_comp, lower_comp, relegated, promoted_direct, promoted_playoff_phase, from_year, source)
values (${[q(id), q(p.region), q(p.upper), q(p.lower), p.relegated, p.promoted_direct, q(p.promoted_playoff_phase), p.from_year, q(p.source)].join(', ')})
on conflict (id) do update set relegated = excluded.relegated, promoted_direct = excluded.promoted_direct,
  promoted_playoff_phase = excluded.promoted_playoff_phase, from_year = excluded.from_year, source = excluded.source;
`
  }
  sql += `
commit;

-- conferência
select competition_id, count(*) as clubes from public.sim_competition_clubs group by 1 order by 1;
`
  await writeFile(P('supabase/evolution/02_reference_data.sql'), sql)
  await writeFile(P('data/clubs/generated_strength.json'), JSON.stringify(Object.fromEntries(clubs.map((c) => [c.id, {
    name: c.name, short: c.short, country: c.country, tier: c.tier, strength: c.strength, full_name: c.full, city: c.city, basis: c.basis,
  }])), null, 1) + '\n')
  // catálogo do app (nome, sigla, cores, país e região de TODOS os clubes) — o escudo desenhado usa as cores
  const old = [...oldSeed.matchAll(/^\('([a-z0-9-]+)',\s*'([^']+)',\s*'([^']+)',\s*'([A-Z]{3})',\s*'([a-z_]+)',\s*\d+,\s*'(#[0-9A-Fa-f]{6})',\s*'(#[0-9A-Fa-f]{6})'\)/gm)]
    .map((m) => ({ id: m[1], name: m[2], short: m[3], country: m[4], tier: m[5] === 'br_other' && ['fortaleza', 'juventude'].includes(m[1]) ? 'serie_b' : m[5],
                   region: m[4] === 'BRA' ? 'BRA' : null, c1: m[6], c2: m[7] }))
  if (old.length !== oldIds.size) throw new Error(`02_seed.sql: li ${old.length} de ${oldIds.size} clubes`)
  const all = [...old, ...clubs]
  let js = `// GERADO por scripts/build-competitions.mjs (a partir de supabase/seasons/02_seed.sql e data/clubs/clubs_evolution.json).
// Nome, sigla, cores, país e região dos clubes (a "força" fica só no banco, onde a simulação roda). Não edite à mão.
export const CLUB_CATALOG = {
`
  for (const c of all) {
    js += `  ${JSON.stringify(c.id).replace(/"/g, "'")}: { id: '${c.id}', name: ${JSON.stringify(c.name).replace(/'/g, "\\'").replace(/^"|"$/g, "'")}, short: '${c.short}', country: '${c.country}', region: ${c.region ? `'${c.region}'` : 'null'}, tier: '${c.tier}', colors: ['${c.c1}', '${c.c2}'] },\n`
  }
  js += '}\n'
  await writeFile(P('src/features/club/data/clubCatalog.js'), js)

  console.log(`OK: ${clubs.length} clubes novos, ${comps.competitions.length} competições, ${rows.length} participações de referência`)
}

main().catch((e) => {
  console.error('ERRO:', e.message)
  process.exit(1)
})
