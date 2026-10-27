#!/usr/bin/env node
/**
 * Importa os ESCUDOS (clubes) e EMBLEMAS (campeonatos) a partir da coleção de SVGs separada por país
 * (a pasta "logos" do arquivo logos.zip: logos/brazil/..., logos/england/..., logos/tournaments/...).
 *
 *   node scripts/import-crests.mjs <pasta-logos>
 *
 * O que faz:
 *   - clubes:     data/clubs/crest_sources.json (id do clube -> arquivo da coleção) -> public/crests/<id>.svg
 *   - palpites:   data/competitions/prediction_emblem_sources.json (nome da competição -> arquivo; "@id" reaproveita
 *                 o emblema do campeonato do modo Temporadas)
 *                 -> public/competitions/pred-<nome>.svg
 *   - gera src/features/club/data/crests.js (CREST_FILES) e src/features/club/data/competitionEmblems.js
 *   - avisa clube do catálogo sem escudo mapeado e arquivo que não existe na coleção.
 * Os emblemas dos 9 campeonatos do modo Temporadas (public/competitions/<id>.svg) vieram dos SVGs enviados
 * separadamente e ficam versionados como estão; o script só os lista em competitionEmblems.js.
 *
 * Arquivos que continuam muito pesados (> 150 KB, p.ex. com imagem embutida) viram WebP de 256 px se o pacote
 * "sharp" estiver disponível (npm i -D sharp); sem ele, o SVG é mantido.
 *
 * Os SVGs são copiados como vieram (inclusive a atribuição da fonte, "Source: football-logos.cc").
 */
import { mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const CREST_DIR = path.join(ROOT, 'public', 'crests')
const COMP_DIR = path.join(ROOT, 'public', 'competitions')
const GAME_COMPS = ['brasileirao', 'serie_b', 'copa_brasil', 'libertadores', 'premier_league', 'championship', 'fa_cup', 'efl_cup', 'ucl']

export { writeEmblem }

// O SVG vai como veio (a limpeza "inteligente" de números quebrava alguns escudos). Só tira espaços nas pontas.
export function optimizeSvg(text) {
  return text.trim()
}

const HEAVY = 150 * 1024
let sharpMod
async function sharp() {
  if (sharpMod === undefined) {
    try { sharpMod = (await import('sharp')).default } catch {
      try { sharpMod = createRequire(import.meta.url)('sharp') } catch { sharpMod = null } // também acha via NODE_PATH
    }
  }
  return sharpMod
}
// grava o SVG limpo; se ficou pesado demais, tenta WebP. Devolve o nome do arquivo gravado.
async function writeEmblem(dir, base, svgText) {
  const svg = optimizeSvg(svgText)
  const sh = svg.length > HEAVY ? await sharp() : null
  if (sh) {
    const buf = await sh(Buffer.from(svg), { density: 300 }).resize({ height: 256, fit: 'inside' }).webp({ quality: 90 }).toBuffer()
    await writeFile(path.join(dir, `${base}.webp`), buf)
    return { file: `${base}.webp`, bytes: buf.length }
  }
  await writeFile(path.join(dir, `${base}.svg`), svg)
  return { file: `${base}.svg`, bytes: svg.length }
}

async function main() {
  const src = process.argv[2]
  if (!src || !existsSync(src)) {
    console.error('Uso: node scripts/import-crests.mjs <pasta-logos>   (a pasta com brazil/, england/, tournaments/ ...)')
    process.exit(1)
  }
  const crestMap = JSON.parse(await readFile(path.join(ROOT, 'data/clubs/crest_sources.json'), 'utf8'))
  const predMap = JSON.parse(await readFile(path.join(ROOT, 'data/competitions/prediction_emblem_sources.json'), 'utf8'))
  const { CLUB_CATALOG } = await import(pathToFileURL(path.join(ROOT, 'src/features/club/data/clubCatalog.js')).href)

  // escudos antigos (baixados da internet) saem: a coleção nova cobre todos os clubes
  await rm(CREST_DIR, { recursive: true, force: true })
  await mkdir(CREST_DIR, { recursive: true })
  await mkdir(COMP_DIR, { recursive: true })

  const problems = []
  const crests = {}
  let bytes = 0
  for (const [id, rel] of Object.entries(crestMap)) {
    if (!CLUB_CATALOG[id]) { problems.push(`clube "${id}" não existe no catálogo`); continue }
    const file = path.join(src, rel)
    if (!existsSync(file)) { problems.push(`${id}: arquivo não encontrado (${rel})`); continue }
    const w = await writeEmblem(CREST_DIR, id, await readFile(file, 'utf8'))
    crests[id] = w.file
    bytes += w.bytes
  }
  for (const id of Object.keys(CLUB_CATALOG)) if (!crests[id]) problems.push(`clube sem escudo: ${id} (${CLUB_CATALOG[id].name})`)

  for (const f of await readdir(COMP_DIR)) if (f.startsWith('pred-')) await rm(path.join(COMP_DIR, f))
  const pred = {}
  const compFiles = await readdir(COMP_DIR)
  const gameFile = (id) => compFiles.find((x) => x === `${id}.svg` || x === `${id}.webp`)
  for (const [name, rel] of Object.entries(predMap)) {
    if (rel.startsWith('@')) { // mesmo campeonato do modo Temporadas: reaproveita o emblema
      if (gameFile(rel.slice(1))) pred[name] = gameFile(rel.slice(1))
      else problems.push(`palpites "${name}": emblema ${rel} não existe`)
      continue
    }
    const file = path.join(src, rel)
    if (!existsSync(file)) { problems.push(`palpites "${name}": arquivo não encontrado (${rel})`); continue }
    const slug = name.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
    const w = await writeEmblem(COMP_DIR, `pred-${slug}`, await readFile(file, 'utf8'))
    pred[name] = w.file
  }
  const game = {}
  for (const id of GAME_COMPS) {
    const f = gameFile(id)
    if (f) game[id] = f
    else problems.push(`campeonato sem emblema: ${id}`)
  }

  await writeFile(path.join(ROOT, 'src/features/club/data/crests.js'), `// GERADO por scripts/import-crests.mjs — não edite à mão (mapa em data/clubs/crest_sources.json).
// Escudo de cada clube em public/crests/. Clube fora daqui usa o escudo desenhado com as cores do clube.
export const CREST_FILES = {
${Object.entries(crests).map(([k, v]) => `  '${k}': '${v}',`).join('\n')}
}
`)
  await writeFile(path.join(ROOT, 'src/features/club/data/competitionEmblems.js'), `// GERADO por scripts/import-crests.mjs — não edite à mão.
// Emblemas em public/competitions/. Modo Temporadas: pelo id do campeonato. Palpites: pelo nome da competição.
export const COMP_EMBLEMS = {
${Object.entries(game).map(([k, v]) => `  '${k}': '${v}',`).join('\n')}
}
export const PREDICTION_EMBLEMS = {
${Object.entries(pred).map(([k, v]) => `  ${JSON.stringify(k)}: '${v}',`).join('\n')}
}
`)
  console.log(`escudos: ${Object.keys(crests).length} (${Math.round(bytes / 1024)} KB) · campeonatos: ${Object.keys(game).length} · palpites: ${Object.keys(pred).length}`)
  if (problems.length) {
    console.log('\nATENÇÃO:\n  ' + problems.join('\n  '))
    process.exitCode = 1
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
