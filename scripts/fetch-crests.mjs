#!/usr/bin/env node
/**
 * Baixa o ESCUDO REAL de todos os clubes cadastrados — automaticamente, sem baixar um por um.
 *
 *   node scripts/fetch-crests.mjs              -> baixa só o que ainda não existe (rode de novo para completar)
 *   node scripts/fetch-crests.mjs --force      -> baixa tudo de novo
 *   node scripts/fetch-crests.mjs --only=vasco,gremio
 *
 * Fontes, em cascata (a primeira que entregar uma imagem válida vence):
 *   1) Wikidata/Commons     -> escudo livre da Wikipedia (sem chave)
 *   2) football-data.org    -> clubes da Série A (usa a sua FOOTBALL_DATA_KEY, se você informar)
 *   3) TheSportsDB          -> base colaborativa de escudos, cobre os clubes sul-americanos (sem chave)
 *   4) Imagem da página     -> imagem principal do artigo da Wikipedia
 * Cada clube que falhar vem com o MOTIVO no relatório. Para forçar um escudo: OVERRIDES (URL direta).
 *
 * Com a chave da football-data (opcional, só melhora os clubes da Série A):
 *   Windows (cmd):  set "FOOTBALL_DATA_KEY=sua_chave" && node scripts/fetch-crests.mjs
 *   PowerShell:     $env:FOOTBALL_DATA_KEY="sua_chave"; node scripts/fetch-crests.mjs
 * Requer Node 18+ e internet.
 */
import { mkdir, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const OUT_DIR = path.join(ROOT, 'public', 'crests')
const INDEX_FILE = path.join(ROOT, 'src', 'features', 'club', 'data', 'crests.js')

const WIDTH = 160
const FOOTBALL_CLUB = 'Q476028'
const UA = 'SimulationFootballGame/1.0 (projeto pessoal; baixa escudos uma vez)'

// Para forçar um escudo: URL direta de uma imagem OU nome de arquivo do Wikimedia Commons.
//   ex.:  'vasco': 'https://exemplo.com/vasco.png'   |   'cusco': 'File:Cusco FC logo.svg'
export const OVERRIDES = {
  'fluminense': 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ad/Fluminense_FC_escudo.png/250px-Fluminense_FC_escudo.png?utm_source=pt.wikipedia.org&utm_campaign=index&utm_content=thumbnail',
  'corinthians': 'https://images.seeklogo.com/logo-png/12/2/s-c-corinthians-paulista-logo-png_seeklogo-121083.png'
}

export const CLUBS = [
  { id: 'flamengo', country: 'Brazil', name: 'Flamengo', wiki: 'CR Flamengo', search: 'Flamengo football club', aliases: ['Flamengo'] },
  { id: 'palmeiras', country: 'Brazil', name: 'Palmeiras', wiki: 'SE Palmeiras', search: 'Palmeiras football club', aliases: ['Palmeiras'] },
  { id: 'botafogo', country: 'Brazil', name: 'Botafogo', wiki: 'Botafogo de Futebol e Regatas', search: 'Botafogo football club', aliases: ['Botafogo'] },
  { id: 'fluminense', country: 'Brazil', name: 'Fluminense', wiki: 'Fluminense FC', search: 'Fluminense football club', aliases: ['Fluminense'] },
  { id: 'cruzeiro', country: 'Brazil', name: 'Cruzeiro', wiki: 'Cruzeiro Esporte Clube', search: 'Cruzeiro football club', aliases: ['Cruzeiro'] },
  { id: 'atletico-mg', country: 'Brazil', name: 'Atlético-MG', wiki: 'Clube Atlético Mineiro', search: 'Clube Atlético Mineiro', aliases: ['Atlético-MG', 'Atletico Mineiro', 'Atlético Mineiro'] },
  { id: 'corinthians', country: 'Brazil', name: 'Corinthians', wiki: 'Sport Club Corinthians Paulista', search: 'Corinthians football club', aliases: ['Corinthians'] },
  { id: 'sao-paulo', country: 'Brazil', name: 'São Paulo', wiki: 'São Paulo FC', search: 'São Paulo football club', aliases: ['São Paulo', 'Sao Paulo'] },
  { id: 'athletico-pr', country: 'Brazil', name: 'Athletico-PR', wiki: 'Club Athletico Paranaense', search: 'Athletico-PR football club', aliases: ['Athletico-PR', 'Athletico Paranaense'] },
  { id: 'bahia', country: 'Brazil', name: 'Bahia', wiki: 'Esporte Clube Bahia', search: 'Bahia football club', aliases: ['Bahia'] },
  { id: 'internacional', country: 'Brazil', name: 'Internacional', wiki: 'Sport Club Internacional', search: 'Sport Club Internacional', aliases: ['Internacional', 'SC Internacional'] },
  { id: 'gremio', country: 'Brazil', name: 'Grêmio', wiki: 'Grêmio Foot-Ball Porto Alegrense', search: 'Grêmio Foot-Ball Porto Alegrense', aliases: ['Grêmio', 'Gremio', 'Gremio FBPA'] },
  { id: 'bragantino', country: 'Brazil', name: 'Red Bull Bragantino', wiki: 'Red Bull Bragantino', search: 'Red Bull Bragantino', aliases: ['Red Bull Bragantino', 'RB Bragantino', 'Bragantino'] },
  { id: 'santos', country: 'Brazil', name: 'Santos', wiki: 'Santos FC', search: 'Santos football club', aliases: ['Santos'] },
  { id: 'vasco', country: 'Brazil', name: 'Vasco da Gama', wiki: 'CR Vasco da Gama', search: 'CR Vasco da Gama', aliases: ['Vasco da Gama', 'Vasco', 'CR Vasco da Gama'] },
  { id: 'coritiba', country: 'Brazil', name: 'Coritiba', wiki: 'Coritiba Foot Ball Club', search: 'Coritiba football club', aliases: ['Coritiba'] },
  { id: 'vitoria', country: 'Brazil', name: 'Vitória', wiki: 'Esporte Clube Vitória', search: 'Vitória football club', aliases: ['Vitória', 'Vitoria', 'EC Vitória'] },
  { id: 'mirassol', country: 'Brazil', name: 'Mirassol', wiki: 'Mirassol Futebol Clube', search: 'Mirassol Futebol Clube', aliases: ['Mirassol'] },
  { id: 'remo', country: 'Brazil', name: 'Remo', wiki: 'Clube do Remo', search: 'Remo football club', aliases: ['Remo'] },
  { id: 'chapecoense', country: 'Brazil', name: 'Chapecoense', wiki: 'Associação Chapecoense de Futebol', search: 'Chapecoense football club', aliases: ['Chapecoense'] },
  { id: 'fortaleza', country: 'Brazil', name: 'Fortaleza', wiki: 'Fortaleza Esporte Clube', search: 'Fortaleza football club', aliases: ['Fortaleza'] },
  { id: 'juventude', country: 'Brazil', name: 'Juventude', wiki: 'Esporte Clube Juventude', search: 'Esporte Clube Juventude', aliases: ['Juventude', 'EC Juventude'] },
  { id: 'estudiantes', country: 'Argentina', name: 'Estudiantes', wiki: 'Estudiantes de La Plata', search: 'Estudiantes de La Plata', aliases: ['Estudiantes', 'Estudiantes LP', 'Estudiantes de La Plata'] },
  { id: 'cusco', country: 'Peru', name: 'Cusco FC', wiki: 'Cusco FC', search: 'Cusco FC', aliases: ['Cusco FC', 'Cusco'] },
  { id: 'ind-medellin', country: 'Colombia', name: 'Independiente Medellín', wiki: 'Independiente Medellín', search: 'Independiente Medellín football club', aliases: ['Independiente Medellín', 'Independiente Medellin'] },
  { id: 'nacional-uru', country: 'Uruguay', name: 'Nacional', wiki: 'Club Nacional de Football', search: 'Nacional football club', aliases: ['Nacional', 'Club Nacional de Football'] },
  { id: 'universitario', country: 'Peru', name: 'Universitario', wiki: 'Club Universitario de Deportes', search: 'Universitario football club', aliases: ['Universitario', 'Universitario de Deportes'] },
  { id: 'coquimbo', country: 'Chile', name: 'Coquimbo Unido', wiki: 'Coquimbo Unido', search: 'Coquimbo Unido', aliases: ['Coquimbo Unido', 'Coquimbo'] },
  { id: 'tolima', country: 'Colombia', name: 'Deportes Tolima', wiki: 'Deportes Tolima', search: 'Deportes Tolima', aliases: ['Deportes Tolima', 'Tolima'] },
  { id: 'bolivar', country: 'Bolivia', name: 'Bolívar', wiki: 'Club Bolívar', search: 'Club Bolívar', aliases: ['Bolívar', 'Bolivar', 'Club Bolivar'] },
  { id: 'la-guaira', country: 'Venezuela', name: 'Deportivo La Guaira', wiki: 'Deportivo La Guaira', search: 'Deportivo La Guaira', aliases: ['Deportivo La Guaira', 'La Guaira'] },
  { id: 'ind-rivadavia', country: 'Argentina', name: 'Independiente Rivadavia', wiki: 'Independiente Rivadavia', search: 'Independiente Rivadavia football club', aliases: ['Independiente Rivadavia'] },
  { id: 'boca-juniors', country: 'Argentina', name: 'Boca Juniors', wiki: 'Boca Juniors', search: 'Boca Juniors football club', aliases: ['Boca Juniors'] },
  { id: 'u-catolica', country: 'Chile', name: 'Universidad Católica', wiki: 'Club Deportivo Universidad Católica', search: 'Universidad Católica football club', aliases: ['Universidad Católica', 'Universidad Catolica'] },
  { id: 'barcelona-sc', country: 'Ecuador', name: 'Barcelona SC', wiki: 'Barcelona S.C.', search: 'Barcelona S.C.', aliases: ['Barcelona SC', 'Barcelona Sporting Club', 'Barcelona Guayaquil'] },
  { id: 'penarol', country: 'Uruguay', name: 'Peñarol', wiki: 'Peñarol', search: 'Peñarol', aliases: ['Peñarol', 'Penarol'] },
  { id: 'santa-fe', country: 'Colombia', name: 'Santa Fe', wiki: 'Independiente Santa Fe', search: 'Independiente Santa Fe', aliases: ['Santa Fe', 'Independiente Santa Fe'] },
  { id: 'platense', country: 'Argentina', name: 'Platense', wiki: 'Club Atlético Platense', search: 'Platense football club', aliases: ['Platense'] },
  { id: 'cerro-porteno', country: 'Paraguay', name: 'Cerro Porteño', wiki: 'Cerro Porteño', search: 'Cerro Porteño football club', aliases: ['Cerro Porteño'] },
  { id: 'junior', country: 'Colombia', name: 'Junior Barranquilla', wiki: 'Atlético Junior', search: 'Junior Barranquilla football club', aliases: ['Junior Barranquilla', 'Junior', 'Junior FC', 'Atlético Junior'] },
  { id: 'sporting-cristal', country: 'Peru', name: 'Sporting Cristal', wiki: 'Sporting Cristal', search: 'Sporting Cristal football club', aliases: ['Sporting Cristal'] },
  { id: 'ldu', country: 'Ecuador', name: 'LDU Quito', wiki: 'LDU Quito', search: 'LDU Quito football club', aliases: ['LDU Quito', 'Liga Deportiva Universitaria'] },
  { id: 'lanus', country: 'Argentina', name: 'Lanús', wiki: 'Club Atlético Lanús', search: 'Club Atlético Lanús', aliases: ['Lanús', 'Lanus'] },
  { id: 'always-ready', country: 'Bolivia', name: 'Always Ready', wiki: 'Club Always Ready', search: 'Club Always Ready', aliases: ['Always Ready', 'Club Always Ready'] },
  { id: 'ind-del-valle', country: 'Ecuador', name: 'Independiente del Valle', wiki: 'Independiente del Valle', search: 'Independiente del Valle football club', aliases: ['Independiente del Valle'] },
  { id: 'libertad', country: 'Paraguay', name: 'Libertad', wiki: 'Club Libertad', search: 'Libertad football club', aliases: ['Libertad', 'Club Libertad'] },
  { id: 'rosario-central', country: 'Argentina', name: 'Rosario Central', wiki: 'Rosario Central', search: 'Rosario Central football club', aliases: ['Rosario Central'] },
  { id: 'u-central', country: 'Venezuela', name: 'Universidad Central', wiki: 'Universidad Central de Venezuela F.C.', search: 'Universidad Central football club', aliases: ['Universidad Central', 'Universidad Central de Venezuela'] },
]

// Clubes da evolução (Premier League, Championship, Champions League e Série B) — lidos de data/clubs/clubs_evolution.json
const COUNTRY_EN = { BRA: 'Brazil', ENG: 'England', WAL: 'Wales', FRA: 'France', GER: 'Germany', ESP: 'Spain', ITA: 'Italy', POR: 'Portugal',
  BEL: 'Belgium', NED: 'Netherlands', NOR: 'Norway', TUR: 'Turkey', UKR: 'Ukraine', CZE: 'Czech Republic', SVK: 'Slovakia', GRE: 'Greece',
  AUT: 'Austria', AZE: 'Azerbaijan' }
{
  const { readFile } = await import('node:fs/promises')
  const evo = JSON.parse(await readFile(path.join(ROOT, 'data', 'clubs', 'clubs_evolution.json'), 'utf8'))
  for (const [id, name, , country, , , , , , full] of evo.clubs) {
    if (CLUBS.some((c) => c.id === id)) continue
    CLUBS.push({ id, country: COUNTRY_EN[country] || country, name, wiki: full, search: `${full}`, aliases: [name, full] })
  }
}

const enc = encodeURIComponent
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// ---- rede (injetável, para teste) com pausa por servidor e novas tentativas ------------------------
const HOST_DELAY = { 'www.thesportsdb.com': 2300, 'api.football-data.org': 6500 } // limites gratuitos: ~30/min e 10/min
export function createNet({ fetchImpl = globalThis.fetch, delayMs = 250, hostDelay = HOST_DELAY, backoffMs = 1500 } = {}) {
  async function request(url, binary, headers = {}) {
    const wait = hostDelay[new URL(url).hostname] ?? delayMs
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const res = await fetchImpl(url, {
          headers: { 'User-Agent': UA, 'Api-User-Agent': UA, Accept: binary ? 'image/*' : 'application/json', ...headers },
          redirect: 'follow',
        })
        if (res.status === 429 || res.status >= 500) {
          await sleep(Math.max(backoffMs * attempt, wait * 2 * attempt))
          continue
        }
        if (!res.ok) return null
        await sleep(wait)
        if (binary) return { buf: Buffer.from(await res.arrayBuffer()), type: res.headers.get('content-type') || '' }
        return await res.json()
      } catch {
        await sleep(backoffMs * attempt)
      }
    }
    return null
  }
  return { json: (url, headers) => request(url, false, headers), bin: (url) => request(url, true) }
}

// ---- nomes: comparação tolerante a acentos e palavras comuns ("FC", "Club", "de"...) ------------
const STOP = /\b(fc|cf|sc|ec|ac|cd|cs|ca|club|clube|de|del|la|los|football|futebol|futbol|deportivo|esporte|associacao|sociedade|regatas|foot|ball)\b/g
export const norm = (s = '') =>
  s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(STOP, ' ').replace(/\s+/g, ' ').trim()

// 3 = igual | 2 = um contém o outro (mín. 4 letras) | 0 = diferente
export function nameScore(candidates, wanted) {
  let best = 0
  for (const c of candidates.map(norm).filter(Boolean)) {
    for (const w of wanted.map(norm).filter(Boolean)) {
      if (c === w) best = Math.max(best, 3)
      else if (Math.min(c.length, w.length) >= 4 && (c.includes(w) || w.includes(c))) best = Math.max(best, 2)
    }
  }
  return best
}

// ---- fonte 1: Wikipedia / Wikidata / Commons -------------------------------------------------------
export async function pageInfo(net, title) {
  const j = await net.json(
    `https://en.wikipedia.org/w/api.php?action=query&format=json&formatversion=2&redirects=1&prop=pageprops%7Cpageimages&ppprop=wikibase_item&piprop=original&titles=${enc(title)}`,
  )
  const page = j?.query?.pages?.[0]
  if (!page || page.missing) return null
  return { qid: page.pageprops?.wikibase_item || null, image: page.original?.source || null }
}

export async function entityClaims(net, qid) {
  const j = await net.json(`https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=claims&ids=${qid}`)
  return j?.entities?.[qid]?.claims || null
}

export function pickLogo(claims) {
  const list = (claims?.P154 || []).filter((c) => c.rank !== 'deprecated' && c.mainsnak?.datavalue?.value && !c.qualifiers?.P582)
  if (!list.length) return null
  const preferred = list.filter((c) => c.rank === 'preferred')
  const pool = preferred.length ? preferred : list
  return pool[pool.length - 1].mainsnak.datavalue.value
}

export const isFootballClub = (claims) => (claims?.P31 || []).some((c) => c.mainsnak?.datavalue?.value?.id === FOOTBALL_CLUB)

export async function searchLogo(net, name) {
  const j = await net.json(`https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&language=en&type=item&limit=6&search=${enc(name)}`)
  for (const hit of j?.search || []) {
    const claims = await entityClaims(net, hit.id)
    if (isFootballClub(claims)) {
      const file = pickLogo(claims)
      if (file) return file
    }
  }
  return null
}

export const commonsUrl = (file) => `https://commons.wikimedia.org/wiki/Special:FilePath/${enc(file.replace(/^File:/i, '').replace(/ /g, '_'))}?width=${WIDTH}`

// ---- fonte 2: football-data.org (só Série A, só com chave) ----------------------------------------
export async function fdCrest(net, club, ctx) {
  if (!ctx.fdKey || club.country !== 'Brazil') return null
  if (ctx.fdTeams === undefined) {
    const j = await net.json('https://api.football-data.org/v4/competitions/BSA/teams', { 'X-Auth-Token': ctx.fdKey })
    ctx.fdTeams = j?.teams || null
  }
  let best = null
  for (const t of ctx.fdTeams || []) {
    const s = nameScore([t.name, t.shortName, t.tla].filter(Boolean), club.aliases)
    if (s >= 2 && (!best || s > best.s)) best = { s, crest: t.crest }
  }
  return best?.crest || null
}

// ---- fonte 3: TheSportsDB -------------------------------------------------------------------------
// Chave gratuita "3" (≈30 req/min). A busca gratuita devolve poucos resultados, então testamos
// vários nomes do clube e filtramos por esporte (futebol), país e semelhança do nome.
export async function sportsDbBadge(net, club, ctx) {
  const key = ctx.sdbKey || '3'
  const queries = [...new Set([...club.aliases, club.search, club.wiki])].slice(0, 5)
  let best = null
  for (const q of queries) {
    const j = await net.json(`https://www.thesportsdb.com/api/v1/json/${key}/searchteams.php?t=${enc(q)}`)
    for (const t of j?.teams || []) {
      if (t.strSport !== 'Soccer') continue
      if (t.strCountry && t.strCountry.toLowerCase() !== club.country.toLowerCase()) continue
      const badge = t.strBadge || t.strTeamBadge
      if (!badge) continue
      const names = [t.strTeam, t.strTeamShort, ...(t.strAlternate || '').split(',').map((x) => x.trim())].filter(Boolean)
      const s = nameScore(names, club.aliases)
      if (s >= 2 && (!best || s > best.s)) best = { s, badge }
    }
    if (best?.s === 3) break // nome idêntico: não precisa tentar os outros
  }
  // "/small" devolve uma versão leve (~250 px); se não existir, usa a imagem original
  return best ? [`${best.badge}/small`, best.badge] : null
}

// ---- cascata de fontes -----------------------------------------------------------------------------
export async function* sources(net, club, ctx) {
  const t = ctx.trace
  const ov = (ctx.overrides || {})[club.id]
  if (ov) {
    yield { how: 'override', urls: [/^https?:/i.test(ov) ? ov : commonsUrl(ov)] }
    return
  }

  const info = await pageInfo(net, club.wiki)
  if (!info) t.push(`Wikipedia: página "${club.wiki}" não encontrada`)
  else if (!info.qid) t.push('Wikipedia: página sem item no Wikidata')
  else {
    const file = pickLogo(await entityClaims(net, info.qid))
    if (file) yield { how: 'wikidata', urls: [commonsUrl(file)] }
    else t.push('Wikidata: sem logotipo livre (o escudo costuma ser arquivo de "uso justo", fora do Commons)')
  }

  const fd = await fdCrest(net, club, ctx)
  if (fd) yield { how: 'football-data.org', urls: [fd] }
  else if (ctx.fdKey && club.country === 'Brazil') t.push('football-data.org: clube fora da Série A 2026')

  const sdb = await sportsDbBadge(net, club, ctx)
  if (sdb) yield { how: 'thesportsdb', urls: sdb }
  else t.push('TheSportsDB: nenhum time compatível (nome/país)')

  const viaSearch = await searchLogo(net, club.search)
  if (viaSearch) yield { how: 'busca no Wikidata', urls: [commonsUrl(viaSearch)] }

  if (info?.image) yield { how: 'imagem da página', urls: [info.image] }
}

const EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif', 'image/svg+xml': 'svg' }

export async function downloadAny(net, urls) {
  for (const url of urls) {
    const r = await net.bin(url)
    const type = r?.type?.split(';')[0].trim().toLowerCase()
    if (r && EXT[type] && r.buf.length >= 200) return { buf: r.buf, ext: EXT[type], url }
  }
  return null
}

// Resolve um clube: devolve a imagem e a fonte, ou null com o motivo em ctx.trace
export async function fetchClubCrest(net, club, ctx) {
  for await (const src of sources(net, club, ctx)) {
    const img = await downloadAny(net, src.urls)
    if (img) return { ...img, how: src.how }
    ctx.trace.push(`${src.how}: a imagem não pôde ser baixada`)
  }
  return null
}

// ---- principal -----------------------------------------------------------------------------------
async function writeIndex() {
  const files = await readdir(OUT_DIR)
  const lines = []
  for (const c of CLUBS) {
    const f = files.find((x) => x.startsWith(`${c.id}.`))
    if (f) lines.push(`  '${c.id}': '${f}',`)
  }
  const text = `// GERADO por scripts/fetch-crests.mjs — não edite à mão.
// Mapa clube -> arquivo do escudo real em public/crests/. Para um clube que não está aqui, o app usa o
// escudo desenhado com as cores do clube.
export const CREST_FILES = {
${lines.join('\n')}
}
`
  await writeFile(INDEX_FILE, text, 'utf8')
  return lines.length
}

export async function main() {
  if (typeof fetch !== 'function') {
    console.error('Este script precisa do Node 18 ou superior (fetch nativo).')
    process.exit(1)
  }
  const args = process.argv.slice(2)
  const force = args.includes('--force')
  const only = args.find((a) => a.startsWith('--only='))?.slice(7).split(',').filter(Boolean)
  const list = only ? CLUBS.filter((c) => only.includes(c.id)) : CLUBS

  await mkdir(OUT_DIR, { recursive: true })
  const existing = await readdir(OUT_DIR)
  const net = createNet()
  const fdKey = (process.env.FOOTBALL_DATA_KEY || '').trim() // trim: no cmd do Windows, "set X=1 && ..." deixa um espaço no fim
  console.log(`Fontes: Wikidata, ${fdKey ? 'football-data.org (chave encontrada), ' : ''}TheSportsDB, Wikipedia\n`)

  const failed = []
  let n = 0
  for (const club of list) {
    n += 1
    const tag = `[${String(n).padStart(2)}/${list.length}] ${club.id.padEnd(17)}`
    if (!force && existing.some((f) => f.startsWith(`${club.id}.`))) {
      console.log(`${tag} já existe`)
      continue
    }
    const ctx = { trace: [], overrides: OVERRIDES, fdKey, sdbKey: (process.env.THESPORTSDB_KEY || '3').trim() }
    const img = await fetchClubCrest(net, club, ctx)
    if (!img) {
      failed.push({ id: club.id, trace: ctx.trace })
      console.log(`${tag} NÃO ENCONTRADO`)
      continue
    }
    await writeFile(path.join(OUT_DIR, `${club.id}.${img.ext}`), img.buf)
    console.log(`${tag} ok  (${img.how}, ${Math.round(img.buf.length / 1024)} KB)`)
  }

  const total = await writeIndex()
  console.log(`\nPronto: ${total} de ${CLUBS.length} escudos disponíveis em public/crests/.`)
  if (failed.length) {
    console.log('\nSem escudo (o app continua usando o desenhado):')
    for (const f of failed) console.log(`  - ${f.id}\n      ${f.trace.join('\n      ') || '(nenhuma fonte respondeu: verifique a internet)'}`)
    console.log('\nPara corrigir um clube: preencha OVERRIDES neste arquivo com a URL de uma imagem e rode de novo.')
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e)
    process.exit(1)
  })
}
