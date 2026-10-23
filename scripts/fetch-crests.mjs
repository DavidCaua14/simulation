#!/usr/bin/env node
/**
 * Baixa o ESCUDO REAL de todos os clubes cadastrados — de uma vez, sem baixar um por um.
 *
 *   node scripts/fetch-crests.mjs            -> baixa só o que ainda não existe
 *   node scripts/fetch-crests.mjs --force    -> baixa tudo de novo
 *   node scripts/fetch-crests.mjs --only=flamengo,boca-juniors
 *
 * Como funciona (APIs públicas e gratuitas, sem chave):
 *   1) Wikipedia  -> acha a página do clube e o item do Wikidata dela
 *   2) Wikidata   -> lê o "logotipo" (propriedade P154) do clube
 *   3) Commons    -> baixa a imagem (PNG de 160 px) para  public/crests/<id>.png
 *   4) Gera       -> src/features/club/data/crests.js (lista dos escudos encontrados)
 * Se um clube não for encontrado, o app continua mostrando o escudo desenhado dele.
 * Para forçar um escudo específico, preencha OVERRIDES abaixo.
 *
 * Requer Node 18 ou superior (usa fetch nativo) e internet.
 */
import { mkdir, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const OUT_DIR = path.join(ROOT, 'public', 'crests')
const INDEX_FILE = path.join(ROOT, 'src', 'features', 'club', 'data', 'crests.js')

const WIDTH = 160 // largura do PNG baixado (px)
const FOOTBALL_CLUB = 'Q476028' // "association football club" no Wikidata
const UA = 'SimulationFootballGame/1.0 (projeto pessoal; baixa escudos uma vez)'

// Troque aqui se algum escudo vier errado: nome do arquivo no Wikimedia Commons OU uma URL direta.
//   ex.: 'cusco': 'File:Cusco FC logo.svg'   |   'remo': 'https://exemplo.com/remo.png'
export const OVERRIDES = {
  'juventude': 'https://commons.wikimedia.org/wiki/File:Juventude_crest.png',
  'estudiantes': 'https://commons.wikimedia.org/wiki/File:Estudiantes_de_la_Plata_crest_(2025).svg',
  'bolivar': 'https://commons.wikimedia.org/wiki/File:Club-bol%C3%ADvar-logo.png',
  'tolima': 'https://commons.wikimedia.org/wiki/Category:Deportes_Tolima_logos?utm_source=chatgpt.com',
  'internacional': 'https://commons.wikimedia.org/w/index.php?curid=21440226',
  'gremio': 'https://commons.wikimedia.org/wiki/File:Gremio_logo.svg',
  'bragantino': 'https://pt.wikipedia.org/w/index.php?curid=6162399'
}

export const CLUBS = [
  { id: 'flamengo', wiki: 'CR Flamengo', search: 'Flamengo football club' },
  { id: 'palmeiras', wiki: 'SE Palmeiras', search: 'Palmeiras football club' },
  { id: 'botafogo', wiki: 'Botafogo de Futebol e Regatas', search: 'Botafogo football club' },
  { id: 'fluminense', wiki: 'Fluminense FC', search: 'Fluminense football club' },
  { id: 'cruzeiro', wiki: 'Cruzeiro Esporte Clube', search: 'Cruzeiro football club' },
  { id: 'atletico-mg', wiki: 'Clube Atlético Mineiro', search: 'Clube Atlético Mineiro' },
  { id: 'corinthians', wiki: 'Sport Club Corinthians Paulista', search: 'Corinthians football club' },
  { id: 'sao-paulo', wiki: 'São Paulo FC', search: 'São Paulo football club' },
  { id: 'athletico-pr', wiki: 'Club Athletico Paranaense', search: 'Athletico-PR football club' },
  { id: 'bahia', wiki: 'Esporte Clube Bahia', search: 'Bahia football club' },
  { id: 'internacional', wiki: 'Sport Club Internacional', search: 'Sport Club Internacional' },
  { id: 'gremio', wiki: 'Grêmio Foot-Ball Porto Alegrense', search: 'Grêmio Foot-Ball Porto Alegrense' },
  { id: 'bragantino', wiki: 'Red Bull Bragantino', search: 'Red Bull Bragantino' },
  { id: 'santos', wiki: 'Santos FC', search: 'Santos football club' },
  { id: 'vasco', wiki: 'CR Vasco da Gama', search: 'CR Vasco da Gama' },
  { id: 'coritiba', wiki: 'Coritiba Foot Ball Club', search: 'Coritiba football club' },
  { id: 'vitoria', wiki: 'Esporte Clube Vitória', search: 'Vitória football club' },
  { id: 'mirassol', wiki: 'Mirassol Futebol Clube', search: 'Mirassol Futebol Clube' },
  { id: 'remo', wiki: 'Clube do Remo', search: 'Remo football club' },
  { id: 'chapecoense', wiki: 'Associação Chapecoense de Futebol', search: 'Chapecoense football club' },
  { id: 'fortaleza', wiki: 'Fortaleza Esporte Clube', search: 'Fortaleza football club' },
  { id: 'juventude', wiki: 'Esporte Clube Juventude', search: 'Esporte Clube Juventude' },
  { id: 'estudiantes', wiki: 'Estudiantes de La Plata', search: 'Estudiantes de La Plata' },
  { id: 'cusco', wiki: 'Cusco FC', search: 'Cusco FC' },
  { id: 'ind-medellin', wiki: 'Independiente Medellín', search: 'Independiente Medellín football club' },
  { id: 'nacional-uru', wiki: 'Club Nacional de Football', search: 'Nacional football club' },
  { id: 'universitario', wiki: 'Club Universitario de Deportes', search: 'Universitario football club' },
  { id: 'coquimbo', wiki: 'Coquimbo Unido', search: 'Coquimbo Unido' },
  { id: 'tolima', wiki: 'Deportes Tolima', search: 'Deportes Tolima' },
  { id: 'bolivar', wiki: 'Club Bolívar', search: 'Club Bolívar' },
  { id: 'la-guaira', wiki: 'Deportivo La Guaira', search: 'Deportivo La Guaira' },
  { id: 'ind-rivadavia', wiki: 'Independiente Rivadavia', search: 'Independiente Rivadavia football club' },
  { id: 'boca-juniors', wiki: 'Boca Juniors', search: 'Boca Juniors football club' },
  { id: 'u-catolica', wiki: 'Club Deportivo Universidad Católica', search: 'Universidad Católica football club' },
  { id: 'barcelona-sc', wiki: 'Barcelona S.C.', search: 'Barcelona S.C.' },
  { id: 'penarol', wiki: 'Peñarol', search: 'Peñarol' },
  { id: 'santa-fe', wiki: 'Independiente Santa Fe', search: 'Independiente Santa Fe' },
  { id: 'platense', wiki: 'Club Atlético Platense', search: 'Platense football club' },
  { id: 'cerro-porteno', wiki: 'Cerro Porteño', search: 'Cerro Porteño football club' },
  { id: 'junior', wiki: 'Atlético Junior', search: 'Junior Barranquilla football club' },
  { id: 'sporting-cristal', wiki: 'Sporting Cristal', search: 'Sporting Cristal football club' },
  { id: 'ldu', wiki: 'LDU Quito', search: 'LDU Quito football club' },
  { id: 'lanus', wiki: 'Club Atlético Lanús', search: 'Club Atlético Lanús' },
  { id: 'always-ready', wiki: 'Club Always Ready', search: 'Club Always Ready' },
  { id: 'ind-del-valle', wiki: 'Independiente del Valle', search: 'Independiente del Valle football club' },
  { id: 'libertad', wiki: 'Club Libertad', search: 'Libertad football club' },
  { id: 'rosario-central', wiki: 'Rosario Central', search: 'Rosario Central football club' },
  { id: 'u-central', wiki: 'Universidad Central de Venezuela F.C.', search: 'Universidad Central football club' },
]

const enc = encodeURIComponent
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// ---- rede (injetável, para teste) ---------------------------------------------------------------
export function createNet({ fetchImpl = globalThis.fetch, delayMs = 250 } = {}) {
  async function request(url, binary) {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const res = await fetchImpl(url, {
          headers: { 'User-Agent': UA, 'Api-User-Agent': UA, Accept: binary ? 'image/*' : 'application/json' },
          redirect: 'follow',
        })
        if (res.status === 429 || res.status >= 500) {
          await sleep(1500 * attempt)
          continue
        }
        if (!res.ok) return null
        await sleep(delayMs) // educado com os servidores
        if (binary) return { buf: Buffer.from(await res.arrayBuffer()), type: res.headers.get('content-type') || '' }
        return await res.json()
      } catch {
        await sleep(1000 * attempt)
      }
    }
    return null
  }
  return { json: (url) => request(url, false), bin: (url) => request(url, true) }
}

// ---- resolução do escudo --------------------------------------------------------------------------
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

// Logotipo atual: ignora os "descontinuados" e os que têm data de fim (logos antigos); prefere o "preferido".
export function pickLogo(claims) {
  const list = (claims?.P154 || []).filter((c) => c.rank !== 'deprecated' && c.mainsnak?.datavalue?.value && !c.qualifiers?.P582)
  if (!list.length) return null
  const preferred = list.filter((c) => c.rank === 'preferred')
  const pool = preferred.length ? preferred : list
  return pool[pool.length - 1].mainsnak.datavalue.value
}

export const isFootballClub = (claims) => (claims?.P31 || []).some((c) => c.mainsnak?.datavalue?.value?.id === FOOTBALL_CLUB)

// Plano B: busca no Wikidata pelo nome e só aceita item que seja "clube de futebol" E tenha logotipo
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

export async function resolveCrest(net, club, overrides = OVERRIDES) {
  const ov = overrides[club.id]
  if (ov) return { how: 'override', url: /^https?:/i.test(ov) ? ov : commonsUrl(ov) }

  const info = await pageInfo(net, club.wiki)
  if (info?.qid) {
    const file = pickLogo(await entityClaims(net, info.qid))
    if (file) return { how: 'wikidata', url: commonsUrl(file) }
  }
  const viaSearch = await searchLogo(net, club.search)
  if (viaSearch) return { how: 'busca', url: commonsUrl(viaSearch) }
  if (info?.image) return { how: 'imagem da página', url: info.image }
  return null
}

const EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif', 'image/svg+xml': 'svg' }

export async function downloadCrest(net, url) {
  const r = await net.bin(url)
  const type = r?.type?.split(';')[0].trim().toLowerCase()
  if (!r || !EXT[type] || r.buf.length < 200) return null
  return { buf: r.buf, ext: EXT[type] }
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
  const failed = []
  let n = 0

  for (const club of list) {
    n += 1
    const tag = `[${String(n).padStart(2)}/${list.length}] ${club.id.padEnd(17)}`
    if (!force && existing.some((f) => f.startsWith(`${club.id}.`))) {
      console.log(`${tag} já existe (use --force para baixar de novo)`)
      continue
    }
    const found = await resolveCrest(net, club)
    const img = found && (await downloadCrest(net, found.url))
    if (!img) {
      failed.push(club.id)
      console.log(`${tag} NÃO ENCONTRADO`)
      continue
    }
    await writeFile(path.join(OUT_DIR, `${club.id}.${img.ext}`), img.buf)
    console.log(`${tag} ok (${found.how}, ${Math.round(img.buf.length / 1024)} KB)`)
  }

  const total = await writeIndex()
  console.log(`\nPronto: ${total} de ${CLUBS.length} escudos disponíveis em public/crests/.`)
  if (failed.length) {
    console.log(`Sem escudo (o app usa o desenhado): ${failed.join(', ')}`)
    console.log('Dica: preencha OVERRIDES neste arquivo com o nome do arquivo no Wikimedia Commons e rode de novo.')
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e)
    process.exit(1)
  })
}
