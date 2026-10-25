#!/usr/bin/env node
/**
 * Gera a base de JOGADORES do modo Carreira (treinador) a partir dos elencos em data/squads/raw/*.txt
 *
 *   node scripts/build-squads.mjs
 *
 * Saídas (todas versionadas no repositório):
 *   data/squads/squads.json                 -> base normalizada (clubes + jogadores + atributos)
 *   data/squads/IMPORT_REPORT.md            -> relatório: fontes, datas, contagens, conflitos e dados estimados
 *   supabase/manager/02_players_seed.sql    -> seed IDEMPOTENTE (pode rodar quantas vezes quiser)
 *
 * Formato de cada arquivo raw (um por clube):
 *   # club: flamengo                       (id do clube em sim_clubs)
 *   # source: https://...                  (de onde veio a lista)
 *   # accessed: 2026-10-24                 (quando foi consultada)
 *   # as_of: 2026-08-30 | unknown          (data do elenco informada pela fonte)
 *   numero|posicao|nacionalidade|nome|observacoes
 *     posicao: GK RB CB LB DM CM AM LM RM RW LW CF ST SS (detalhada) ou GK DF MF FW (ampla); "CB/RB" = principal/secundária
 *     numero:  "-" quando a fonte não informa
 *
 * Regras:
 *  - Nada é inventado: nomes, clubes, números, posições e nacionalidades vêm das fontes.
 *  - Quando a fonte só traz a posição AMPLA (DF/MF/FW), a posição detalhada é ESTIMADA e marcada (position_estimated).
 *  - ATRIBUTOS são uma ESTIMATIVA DE GAMEPLAY (não são estatísticas oficiais): força do clube + papel no elenco
 *    + perfil da posição + variação determinística (sempre o mesmo valor para o mesmo jogador).
 *  - O mesmo jogador em duas listas (transferência no meio do ano): fica no clube cuja lista é MAIS RECENTE.
 *    Apelidos de uma palavra só (ex.: "Vitinho") são tratados como jogadores diferentes, a não ser que a
 *    observação "on loan from <clube>" ligue os dois.
 */
import { readFile, readdir, writeFile, mkdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const RAW_DIR = path.join(ROOT, 'data', 'squads', 'raw')
const OUT_JSON = path.join(ROOT, 'data', 'squads', 'squads.json')
const OUT_REPORT = path.join(ROOT, 'data', 'squads', 'IMPORT_REPORT.md')
const OUT_SQL = path.join(ROOT, 'supabase', 'manager', '02_players_seed.sql')
const CLUB_SEED = path.join(ROOT, 'supabase', 'seasons', '02_seed.sql')
const UNKNOWN_DATE = '2026-01-01' // "as_of: unknown" perde qualquer conflito

// Dados fixos dos clubes (nome oficial e cidade) — complementam sim_clubs
const CLUB_META = {
  flamengo: ['Clube de Regatas do Flamengo', 'Rio de Janeiro'],
  palmeiras: ['Sociedade Esportiva Palmeiras', 'São Paulo'],
  botafogo: ['Botafogo de Futebol e Regatas', 'Rio de Janeiro'],
  fluminense: ['Fluminense Football Club', 'Rio de Janeiro'],
  cruzeiro: ['Cruzeiro Esporte Clube', 'Belo Horizonte'],
  'atletico-mg': ['Clube Atlético Mineiro', 'Belo Horizonte'],
  corinthians: ['Sport Club Corinthians Paulista', 'São Paulo'],
  'sao-paulo': ['São Paulo Futebol Clube', 'São Paulo'],
  'athletico-pr': ['Club Athletico Paranaense', 'Curitiba'],
  bahia: ['Esporte Clube Bahia', 'Salvador'],
  internacional: ['Sport Club Internacional', 'Porto Alegre'],
  gremio: ['Grêmio Foot-Ball Porto Alegrense', 'Porto Alegre'],
  bragantino: ['Red Bull Bragantino', 'Bragança Paulista'],
  santos: ['Santos Futebol Clube', 'Santos'],
  vasco: ['Club de Regatas Vasco da Gama', 'Rio de Janeiro'],
  coritiba: ['Coritiba Foot Ball Club', 'Curitiba'],
  vitoria: ['Esporte Clube Vitória', 'Salvador'],
  mirassol: ['Mirassol Futebol Clube', 'Mirassol'],
  remo: ['Clube do Remo', 'Belém'],
  chapecoense: ['Associação Chapecoense de Futebol', 'Chapecó'],
  fortaleza: ['Fortaleza Esporte Clube', 'Fortaleza'],
  juventude: ['Esporte Clube Juventude', 'Caxias do Sul'],
  estudiantes: ['Club Estudiantes de La Plata', 'La Plata'],
  cusco: ['Cusco Fútbol Club', 'Cusco'],
  'ind-medellin': ['Deportivo Independiente Medellín', 'Medellín'],
  'nacional-uru': ['Club Nacional de Football', 'Montevidéu'],
  universitario: ['Club Universitario de Deportes', 'Lima'],
  coquimbo: ['Club de Deportes Coquimbo Unido', 'Coquimbo'],
  tolima: ['Club Deportes Tolima', 'Ibagué'],
  bolivar: ['Club Bolívar', 'La Paz'],
  'la-guaira': ['Deportivo La Guaira Fútbol Club', 'Caracas'],
  'ind-rivadavia': ['Club Sportivo Independiente Rivadavia', 'Mendoza'],
  'boca-juniors': ['Club Atlético Boca Juniors', 'Buenos Aires'],
  'u-catolica': ['Club Deportivo Universidad Católica', 'Santiago'],
  'barcelona-sc': ['Barcelona Sporting Club', 'Guayaquil'],
  penarol: ['Club Atlético Peñarol', 'Montevidéu'],
  'santa-fe': ['Independiente Santa Fe', 'Bogotá'],
  platense: ['Club Atlético Platense', 'Vicente López'],
  'cerro-porteno': ['Club Cerro Porteño', 'Assunção'],
  junior: ['Club Atlético Junior', 'Barranquilla'],
  'sporting-cristal': ['Club Sporting Cristal', 'Lima'],
  ldu: ['Liga Deportiva Universitaria de Quito', 'Quito'],
  lanus: ['Club Atlético Lanús', 'Lanús'],
  'always-ready': ['Club Always Ready', 'El Alto'],
  'ind-del-valle': ['Independiente del Valle', 'Sangolquí'],
  libertad: ['Club Libertad', 'Assunção'],
  'rosario-central': ['Club Atlético Rosario Central', 'Rosário'],
  'u-central': ['Universidad Central de Venezuela Fútbol Club', 'Caracas'],
}

// ---------------------------------------------------------------------------
// Posições
// ---------------------------------------------------------------------------
const DETAILED = {
  GK: 'GOL', RB: 'LD', RWB: 'LD', LB: 'LE', LWB: 'LE', CB: 'ZAG', SW: 'ZAG',
  DM: 'VOL', CDM: 'VOL', CM: 'MC', AM: 'MEI', CAM: 'MEI', LM: 'PE', RM: 'PD',
  RW: 'PD', LW: 'PE', CF: 'ATA', ST: 'ATA', SS: 'ATA',
}
const BROAD = { DF: 'DEF', MF: 'MID', FW: 'ATT', GK: 'GK' }
const LINE_OF = { GOL: 'GK', LD: 'DEF', LE: 'DEF', ZAG: 'DEF', VOL: 'MID', MC: 'MID', MEI: 'MID', PD: 'ATT', PE: 'ATT', ATA: 'ATT' }
const EST_SECONDARY = { LD: ['LE'], LE: ['LD'], ZAG: [], VOL: ['MC'], MC: ['VOL', 'MEI'], MEI: ['MC'], PD: ['PE'], PE: ['PD'], ATA: [], GOL: [] }
// dicas pelo número da camisa (só para posições AMPLAS) + cotas mínimas por clube
const NUMBER_HINT = {
  DEF: { 2: 'LD', 12: 'LD', 22: 'LD', 6: 'LE', 16: 'LE', 26: 'LE', 36: 'LE', 3: 'ZAG', 4: 'ZAG', 5: 'ZAG', 13: 'ZAG', 14: 'ZAG', 15: 'ZAG', 33: 'ZAG', 44: 'ZAG' },
  MID: { 5: 'VOL', 15: 'VOL', 25: 'VOL', 8: 'MC', 18: 'MC', 28: 'MC', 10: 'MEI', 20: 'MEI', 30: 'MEI' },
  ATT: { 7: 'PD', 17: 'PD', 27: 'PD', 11: 'PE', 21: 'PE', 77: 'PD', 9: 'ATA', 19: 'ATA', 99: 'ATA' },
}
const QUOTA = { DEF: ['LD', 'LE', 'ZAG', 'ZAG', 'LD', 'LE', 'ZAG', 'ZAG'], MID: ['VOL', 'MC', 'MEI', 'VOL', 'MC', 'MEI'], ATT: ['ATA', 'PD', 'PE', 'ATA', 'PD', 'PE'] }

// ---------------------------------------------------------------------------
// Atributos (estimativa de gameplay)
// ---------------------------------------------------------------------------
export const ATTRS = ['gk_reflexes', 'gk_handling', 'gk_positioning', 'marking', 'tackling', 'positioning', 'heading',
  'passing', 'vision', 'technique', 'stamina', 'finishing', 'off_ball', 'pace', 'dribbling', 'strength']

// deslocamento de cada atributo em relação ao nível do jogador, por posição
const TEMPLATE = {
  GOL: { gk_reflexes: 6, gk_handling: 4, gk_positioning: 4, marking: -38, tackling: -38, positioning: -30, heading: -28, passing: -16, vision: -20, technique: -22, stamina: -14, finishing: -48, off_ball: -46, pace: -24, dribbling: -36, strength: -6 },
  ZAG: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: 6, tackling: 6, positioning: 6, heading: 7, passing: -6, vision: -12, technique: -10, stamina: -2, finishing: -26, off_ball: -20, pace: -6, dribbling: -16, strength: 5 },
  LD: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: 1, tackling: 2, positioning: 0, heading: -7, passing: -1, vision: -6, technique: -3, stamina: 6, finishing: -18, off_ball: -5, pace: 6, dribbling: -2, strength: -4 },
  LE: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: 1, tackling: 2, positioning: 0, heading: -7, passing: -1, vision: -6, technique: -3, stamina: 6, finishing: -18, off_ball: -5, pace: 6, dribbling: -2, strength: -4 },
  VOL: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: 4, tackling: 5, positioning: 4, heading: -2, passing: 1, vision: -3, technique: -2, stamina: 5, finishing: -16, off_ball: -12, pace: -6, dribbling: -8, strength: 3 },
  MC: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: -3, tackling: -1, positioning: -1, heading: -7, passing: 5, vision: 3, technique: 3, stamina: 5, finishing: -9, off_ball: -4, pace: -4, dribbling: -1, strength: -2 },
  MEI: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: -16, tackling: -14, positioning: -12, heading: -12, passing: 5, vision: 7, technique: 6, stamina: -1, finishing: -4, off_ball: 2, pace: -3, dribbling: 4, strength: -6 },
  PD: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: -18, tackling: -16, positioning: -16, heading: -12, passing: -2, vision: -4, technique: 3, stamina: 2, finishing: -3, off_ball: 3, pace: 8, dribbling: 6, strength: -6 },
  PE: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: -18, tackling: -16, positioning: -16, heading: -12, passing: -2, vision: -4, technique: 3, stamina: 2, finishing: -3, off_ball: 3, pace: 8, dribbling: 6, strength: -6 },
  ATA: { gk_reflexes: -52, gk_handling: -52, gk_positioning: -52, marking: -24, tackling: -22, positioning: -20, heading: 2, passing: -8, vision: -9, technique: -2, stamina: -4, finishing: 8, off_ball: 6, pace: 1, dribbling: -1, strength: 3 },
}
// pesos usados para a NOTA por posição — iguais aos da tabela sim_role_weights (01_schema.sql)
export const ROLE_WEIGHTS = {
  GOL: { gk_reflexes: 4, gk_handling: 3, gk_positioning: 3, passing: 0.5 },
  ZAG: { marking: 3, tackling: 3, positioning: 3, heading: 2.5, strength: 1.5, pace: 1, passing: 1 },
  LD: { tackling: 2, marking: 2, positioning: 1.5, pace: 2.5, stamina: 2, passing: 1.5, dribbling: 1, technique: 1 },
  LE: { tackling: 2, marking: 2, positioning: 1.5, pace: 2.5, stamina: 2, passing: 1.5, dribbling: 1, technique: 1 },
  VOL: { tackling: 3, marking: 2, positioning: 2.5, passing: 2, stamina: 2, strength: 1, vision: 1 },
  MC: { passing: 3, vision: 2, technique: 2, stamina: 2, tackling: 1, positioning: 1, off_ball: 0.5, finishing: 0.5 },
  MEI: { vision: 3, passing: 2.5, technique: 2.5, dribbling: 2, off_ball: 1.5, finishing: 1.5 },
  PD: { pace: 2.5, dribbling: 2.5, technique: 2, off_ball: 1.5, finishing: 1.5, passing: 1, stamina: 1 },
  PE: { pace: 2.5, dribbling: 2.5, technique: 2, off_ball: 1.5, finishing: 1.5, passing: 1, stamina: 1 },
  ATA: { finishing: 3.5, off_ball: 2.5, heading: 1.5, strength: 1.5, pace: 1.5, technique: 1, dribbling: 1 },
}
export const METHOD = 'v1: força do clube (sim_clubs.strength) + papel no elenco (camisa/capitão/base) + perfil da posição + variação determinística por jogador'

// ---------------------------------------------------------------------------
// utilidades
// ---------------------------------------------------------------------------
function hash01(str) {
  let h = 2166136261
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  h ^= h >>> 13
  h = Math.imul(h, 0x5bd1e995)
  h ^= h >>> 15
  return (h >>> 0) / 4294967296
}
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const strip = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '')
const norm = (s) => strip(s).toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
const slug = (s) => norm(s).replace(/ /g, '-')
const isAbbrev = (name) => /^[A-ZÁÉÍÓÚÂÊÔÃÕÇ]\.\s/u.test(name)
const PARTICLES = new Set(['de', 'da', 'do', 'dos', 'das', 'del', 'la', 'van', 'von'])
// nomes e sobrenomes muito comuns: "João Pedro" ou "Matheus Pereira" podem ser jogadores diferentes,
// então um conflito só é resolvido sozinho quando o nome tem pelo menos uma parte "rara"
const COMMON = new Set(('joao pedro paulo vitor victor gustavo henrique luiz luis carlos eduardo hugo lucas matheus mateus gabriel bruno '
  + 'rafael marcos marcus vinicius felipe guilherme diego juan jose antonio miguel andre ricardo rodrigo daniel thiago tiago leonardo leo '
  + 'fernando fabio fabricio igor caio kaio kaua kaue ryan davi david samuel arthur artur enzo nicolas alex alexandre alexis emerson '
  + 'everton wellington william willian anderson jean junior jr filho neto santos silva souza sousa oliveira pereira costa alves lima '
  + 'ferreira rocha ribeiro rodrigues gomes martins araujo carvalho barbosa melo moura nascimento cardoso teixeira mendes nunes freitas '
  + 'ramos pinto vieira cruz moreira castro duarte dias machado campos lopes '
  + 'hernandez rodriguez gonzalez gomez martinez lopez perez sanchez ramirez torres diaz fernandez garcia castillo morales rojas vargas '
  + 'mendoza flores herrera medina ortiz romero suarez cabrera ruiz nunez moreno alvarez jimenez gutierrez mena valencia angulo '
  + 'quinones caicedo palacios mosquera').split(/\s+/))
function isDistinctive(name) {
  const tokens = norm(name).split(' ').filter((t) => t.length > 1 && !PARTICLES.has(t))
  return tokens.some((t) => !COMMON.has(t))
}

function shortName(full) {
  if (full.length <= 18) return full
  const parts = full.split(' ')
  const first = parts[0]
  let rest = parts.slice(1)
  // mantém partículas antes do sobrenome (ex.: "de Arrascaeta")
  const short = `${first[0]}. ${rest.join(' ')}`
  if (short.length <= 20) return short
  rest = rest.filter((p, i) => i === rest.length - 1 || PARTICLES.has(p.toLowerCase()) === false).slice(-1)
  return `${first[0]}. ${rest.join(' ')}`
}
function abbrKey(name, nat) {
  const n = norm(name).split(' ').filter((t) => !PARTICLES.has(t))
  if (n.length < 2) return null
  return `${n[0][0]}|${n[n.length - 1]}|${nat}`
}

function parsePositions(code) {
  const parts = code.split('/').map((s) => s.trim().toUpperCase()).filter(Boolean)
  const det = parts.map((p) => DETAILED[p]).filter(Boolean)
  if (det.length && parts[0] !== 'DF' && parts[0] !== 'MF' && parts[0] !== 'FW') {
    return { primary: det[0], secondary: [...new Set(det.slice(1))].filter((p) => p !== det[0]), estimated: false }
  }
  const broad = BROAD[parts[0]]
  if (!broad) throw new Error(`Posição desconhecida: ${code}`)
  return { broad, estimated: true }
}

// ---------------------------------------------------------------------------
// leitura
// ---------------------------------------------------------------------------
async function readClubStrength() {
  const sql = await readFile(CLUB_SEED, 'utf8')
  const map = {}
  const re = /\('([a-z0-9-]+)',\s*'([^']+)',\s*'([^']+)',\s*'([A-Z]{3})',\s*'([a-z_]+)',\s*(\d+),/g
  let m
  while ((m = re.exec(sql))) map[m[1]] = { name: m[2], short: m[3], country: m[4], tier: m[5], strength: Number(m[6]) }
  return map
}

async function readRaw() {
  const files = (await readdir(RAW_DIR)).filter((f) => f.endsWith('.txt')).sort()
  const clubs = []
  for (const f of files) {
    const text = await readFile(path.join(RAW_DIR, f), 'utf8')
    const meta = { notes: [] }
    const rows = []
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim()
      if (!line) continue
      if (line.startsWith('#')) {
        const m = line.match(/^#\s*([a-z_]+):\s*(.*)$/)
        if (m) {
          if (m[1] === 'note') meta.notes.push(m[2])
          else meta[m[1]] = m[2].trim()
        }
        continue
      }
      const [num, pos, nat, name, notes = ''] = line.split('|').map((s) => s.trim())
      if (!name) throw new Error(`${f}: linha sem nome -> ${line}`)
      rows.push({ num: /^\d+$/.test(num) ? Number(num) : null, pos, nat: nat && nat !== '?' ? nat.toUpperCase() : null, name, notes })
    }
    if (!meta.club) throw new Error(`${f}: falta "# club:"`)
    meta.asOfSort = meta.as_of && meta.as_of !== 'unknown' ? meta.as_of : UNKNOWN_DATE
    clubs.push({ file: f, ...meta, rows })
  }
  return clubs
}

// ---------------------------------------------------------------------------
// montagem
// ---------------------------------------------------------------------------
function assignEstimatedPositions(club) {
  // posições amplas -> detalhadas: dica do número da camisa, depois cotas mínimas
  for (const line of ['DEF', 'MID', 'ATT']) {
    const group = club.players.filter((p) => p.estimated && p.broad === line)
    if (!group.length) continue
    const have = {}
    const add = (p, pos) => {
      p.primary = pos
      have[pos] = (have[pos] || 0) + 1
    }
    // jogadores com posição detalhada já conhecida também contam na cota
    for (const p of club.players) if (!p.estimated && LINE_OF[p.primary] === line) have[p.primary] = (have[p.primary] || 0) + 1
    const rest = []
    for (const p of group) {
      const hint = p.num != null ? NUMBER_HINT[line][p.num] : null
      if (hint) add(p, hint)
      else rest.push(p)
    }
    rest.sort((a, b) => hash01(`pos:${a.id}`) - hash01(`pos:${b.id}`))
    for (const p of rest) {
      const need = QUOTA[line].find((pos, i) => (have[pos] || 0) < QUOTA[line].slice(0, i + 1).filter((x) => x === pos).length)
      add(p, need || QUOTA[line][Math.floor(hash01(`q:${p.id}`) * 3)])
    }
    for (const p of group) p.secondary = EST_SECONDARY[p.primary] || []
  }
  for (const p of club.players) if (p.estimated && p.broad === 'GK') {
    p.primary = 'GOL'
    p.secondary = []
  }
}

function rating(attrs, pos) {
  const w = ROLE_WEIGHTS[pos]
  let s = 0
  let t = 0
  for (const [k, v] of Object.entries(w)) {
    s += attrs[k] * v
    t += v
  }
  return s / t
}

function makeAttributes(p, clubStrength, squadSize) {
  let role = 0
  const notes = p.notes.toLowerCase()
  if (p.num != null) role += p.num <= 11 ? 3 : p.num <= 25 ? 0 : p.num <= 39 ? -3 : -5
  else if (squadSize > 34) role -= 1
  if (/youth|academy|base/.test(notes)) role = -7
  if (/captain|capit/.test(notes)) role += 2
  const level = clamp(Math.round(clubStrength + role + (hash01(`lvl:${p.id}`) - 0.5) * 9), 40, 90)
  const tpl = TEMPLATE[p.primary]
  const attrs = {}
  for (const a of ATTRS) attrs[a] = level + tpl[a] + Math.round((hash01(`${a}:${p.id}`) - 0.5) * 10)
  // ajusta para que a nota na posição principal fique no nível do jogador
  const shift = Math.round(level - rating(attrs, p.primary))
  for (const a of ATTRS) attrs[a] = clamp(attrs[a] + shift, 12, 96)
  return { level, attrs, overall: Math.round(rating(attrs, p.primary)) }
}

async function main() {
  const strength = await readClubStrength()
  const raw = await readRaw()
  const report = { conflicts: [], warnings: [] }

  // 1) normaliza
  const clubs = raw.map((c) => {
    if (!strength[c.club]) throw new Error(`${c.file}: clube "${c.club}" não existe em supabase/seasons/02_seed.sql`)
    const players = c.rows.map((r) => {
      const pos = parsePositions(r.pos)
      return {
        club: c.club, num: r.num, nat: r.nat, name: r.name, notes: r.notes,
        primary: pos.primary || null, secondary: pos.secondary || [], estimated: pos.estimated, broad: pos.broad || null,
        asOf: c.asOfSort, captain: /captain|capit/i.test(r.notes) && !/vice/i.test(r.notes),
        youth: /youth|academy/i.test(r.notes), loanFrom: (r.notes.match(/on loan from ([^,;]+)/i) || [])[1] || null,
      }
    })
    return { ...c, players }
  })

  // 2) conflitos entre clubes (mesmo jogador em duas listas)
  const all = clubs.flatMap((c) => c.players)
  const byFull = new Map()
  for (const p of all) {
    const tokens = norm(p.name).split(' ')
    if (isAbbrev(p.name) || tokens.length < 2 || !isDistinctive(p.name)) continue
    const k = `${norm(p.name)}|${p.nat}`
    if (!byFull.has(k)) byFull.set(k, [])
    byFull.get(k).push(p)
  }
  const byAbbr = new Map()
  for (const p of all) {
    const k = abbrKey(p.name, p.nat)
    if (!k || !isDistinctive(norm(p.name).split(' ').slice(-1)[0])) continue
    if (!byAbbr.has(k)) byAbbr.set(k, [])
    byAbbr.get(k).push(p)
  }
  const dropped = new Set()
  const resolve = (group, why) => {
    const clubsIn = new Set(group.map((p) => p.club))
    if (clubsIn.size < 2) return
    const sorted = [...group].sort((a, b) => (b.asOf > a.asOf ? 1 : b.asOf < a.asOf ? -1 : 0))
    const keep = sorted[0]
    for (const p of sorted.slice(1)) {
      if (p.club === keep.club) continue
      dropped.add(p)
      report.conflicts.push({ name: keep.name, kept: keep.club, keptAsOf: keep.asOf, dropped: p.club, droppedAsOf: p.asOf, droppedName: p.name, why })
    }
  }
  for (const g of byFull.values()) resolve(g, 'mesmo nome completo e nacionalidade')
  for (const g of byAbbr.values()) {
    const live = g.filter((p) => !dropped.has(p))
    const abbr = live.filter((p) => isAbbrev(p.name))
    const full = live.filter((p) => !isAbbrev(p.name))
    if (!abbr.length || !full.length) continue
    for (const a of abbr) {
      const sameLine = full.filter((f) => f.club !== a.club && (LINE_OF[f.primary] || BROAD_LINE(f)) === BROAD_LINE(a))
      if (sameLine.length === 1) resolve([a, sameLine[0]], 'nome abreviado + sobrenome + nacionalidade')
    }
  }
  // empréstimo: "X on loan from <clube>" e o clube de origem também lista X (apelido de uma palavra)
  for (const p of all) {
    if (!p.loanFrom || dropped.has(p)) continue
    const fromClub = clubs.find((c) => norm(strength[c.club].name) === norm(p.loanFrom) || norm(c.club.replace('-', ' ')) === norm(p.loanFrom))
    if (!fromClub) continue
    for (const q of fromClub.players) {
      if (dropped.has(q) || norm(q.name) !== norm(p.name)) continue
      dropped.add(q)
      report.conflicts.push({ name: p.name, kept: p.club, keptAsOf: p.asOf, dropped: q.club, droppedAsOf: q.asOf, droppedName: q.name, why: `emprestado por ${fromClub.club}` })
    }
  }
  function BROAD_LINE(p) {
    if (p.primary) return LINE_OF[p.primary]
    return p.broad
  }
  for (const c of clubs) c.players = c.players.filter((p) => !dropped.has(p))

  // 3) ids estáveis: nome + nacionalidade; homônimos ganham o clube no fim
  const idCount = new Map()
  for (const p of clubs.flatMap((c) => c.players)) {
    const base = `${slug(p.name)}${p.nat ? `-${p.nat.toLowerCase()}` : ''}`
    p.baseId = base
    idCount.set(base, (idCount.get(base) || 0) + 1)
  }
  const used = new Set()
  for (const p of clubs.flatMap((c) => c.players)) {
    let id = idCount.get(p.baseId) > 1 ? `${p.baseId}-${p.club}` : p.baseId
    let n = 2
    while (used.has(id)) id = `${p.baseId}-${p.club}-${n++}`
    used.add(id)
    p.id = id
  }

  // 4) posições estimadas e atributos
  for (const c of clubs) {
    assignEstimatedPositions(c)
    for (const p of c.players) {
      if (!p.primary) throw new Error(`${c.club}: ${p.name} ficou sem posição`)
      const est = makeAttributes(p, strength[c.club].strength, c.players.length)
      p.level = est.level
      p.attrs = est.attrs
      p.overall = est.overall
    }
    const lines = { GK: 0, DEF: 0, MID: 0, ATT: 0 }
    for (const p of c.players) lines[LINE_OF[p.primary]]++
    if (lines.GK < 2 || lines.DEF < 5 || lines.MID < 4 || lines.ATT < 3) {
      report.warnings.push(`${c.club}: elenco curto em alguma linha (GOL ${lines.GK}, DEF ${lines.DEF}, MEI ${lines.MID}, ATA ${lines.ATT})`)
    }
    if (c.players.length < 18) report.warnings.push(`${c.club}: só ${c.players.length} jogadores`)
    c.lines = lines
  }
  const missingClubs = Object.keys(strength).filter((id) => !clubs.some((c) => c.club === id))
  for (const id of missingClubs) report.warnings.push(`${id}: sem arquivo de elenco (o clube joga com elenco não importado)`)

  // 5) saídas
  const players = clubs.flatMap((c) => c.players)
  const json = {
    generated_at: new Date().toISOString(),
    method: METHOD,
    clubs: clubs.map((c) => ({
      id: c.club, full_name: CLUB_META[c.club]?.[0] ?? null, city: CLUB_META[c.club]?.[1] ?? null,
      source: c.source, accessed: c.accessed, as_of: c.as_of, notes: c.notes, players: c.players.length,
    })),
    players: players.map((p) => ({
      id: p.id, name: p.name, short_name: shortName(p.name), club: p.club, number: p.num, nationality: p.nat,
      position: p.primary, secondary: p.secondary, position_estimated: p.estimated, captain: p.captain, youth: p.youth,
      notes: p.notes || null, overall: p.overall, attrs: p.attrs,
    })),
  }
  await mkdir(path.dirname(OUT_JSON), { recursive: true })
  await writeFile(OUT_JSON, JSON.stringify(json, null, 1) + '\n')

  const q = (v) => (v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`)
  const arr = (a) => (a && a.length ? `array[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`)
  const sourceOf = Object.fromEntries(clubs.map((c) => [c.club, c]))
  let sql = `-- =====================================================================
-- MODO CARREIRA (TREINADOR) — 2/5: CLUBES E JOGADORES (gerado por scripts/build-squads.mjs)
-- NÃO edite à mão: edite data/squads/raw/*.txt e rode  node scripts/build-squads.mjs
-- Idempotente: pode rodar de novo. Jogadores que saíram das listas ficam inativos (não são apagados).
-- Atributos = ESTIMATIVA DE GAMEPLAY (${METHOD}).
-- Atributos com estimated = false (editados à mão) NÃO são sobrescritos.
-- =====================================================================
begin;

-- nome oficial e cidade dos clubes
`
  for (const [id, [full, city]] of Object.entries(CLUB_META)) {
    sql += `update public.sim_clubs set full_name = ${q(full)}, city = ${q(city)} where id = ${q(id)};\n`
  }
  sql += `\ninsert into public.sim_players (id, full_name, short_name, club_id, shirt_number, position, secondary_positions, position_estimated, nationality, is_captain, is_youth, notes, active, source_url, source_as_of, imported_at) values\n`
  sql += players.map((p) => {
    const c = sourceOf[p.club]
    const asOf = c.as_of && c.as_of !== 'unknown' ? q(c.as_of) : 'null'
    return `(${q(p.id)}, ${q(p.name)}, ${q(shortName(p.name))}, ${q(p.club)}, ${p.num ?? 'null'}, ${q(p.primary)}, ${arr(p.secondary)}, ${p.estimated}, ${q(p.nat)}, ${p.captain}, ${p.youth}, ${q(p.notes || null)}, true, ${q(c.source)}, ${asOf}, now())`
  }).join(',\n')
  sql += `\non conflict (id) do update set
  full_name = excluded.full_name, short_name = excluded.short_name, club_id = excluded.club_id, shirt_number = excluded.shirt_number,
  position = excluded.position, secondary_positions = excluded.secondary_positions, position_estimated = excluded.position_estimated,
  nationality = excluded.nationality, is_captain = excluded.is_captain, is_youth = excluded.is_youth, notes = excluded.notes,
  active = true, source_url = excluded.source_url, source_as_of = excluded.source_as_of, imported_at = excluded.imported_at;

-- quem não está mais em nenhuma lista fica inativo e sem clube (o histórico continua apontando para ele)
update public.sim_players set active = false, club_id = null
 where id not in (${players.map((p) => q(p.id)).join(',')});

insert into public.sim_player_attrs (player_id, ${ATTRS.join(', ')}, estimated, method, updated_at) values\n`
  sql += players.map((p) => `(${q(p.id)}, ${ATTRS.map((a) => p.attrs[a]).join(', ')}, true, ${q(METHOD)}, now())`).join(',\n')
  sql += `\non conflict (player_id) do update set
  ${ATTRS.map((a) => `${a} = excluded.${a}`).join(', ')}, method = excluded.method, updated_at = now()
  where public.sim_player_attrs.estimated;   -- atributos curados à mão (estimated = false) são preservados

select public.sim_refresh_ratings();
commit;

-- conferência
select c.id, count(p.*) as jogadores from public.sim_clubs c left join public.sim_players p on p.club_id = c.id and p.active group by c.id order by 1;
`
  await writeFile(OUT_SQL, sql)

  // relatório
  const fmtDate = (d) => (d && d !== 'unknown' ? d : 'desconhecida')
  let md = `# Relatório de importação dos elencos\n\nGerado por \`node scripts/build-squads.mjs\` em ${new Date().toISOString().slice(0, 10)}.\n\n`
  md += `- **Clubes com elenco:** ${clubs.length} de ${Object.keys(strength).length}\n- **Jogadores importados:** ${players.length}\n`
  md += `- **Posição detalhada estimada** (fonte só informava GOL/DEF/MEI/ATA): ${players.filter((p) => p.estimated).length}\n`
  md += `- **Conflitos resolvidos** (jogador em duas listas): ${report.conflicts.length}\n\n`
  md += `> **Atributos:** são uma *estimativa de gameplay*, não estatísticas oficiais. Método: ${METHOD}.\n> Para curar um jogador, edite os atributos em \`sim_player_attrs\` e marque \`estimated = false\` — a importação não sobrescreve.\n\n`
  md += `## Clubes\n\n| Clube | Jogadores | GOL/DEF/MEI/ATA | Pos. estimadas | Data do elenco | Fonte |\n|---|---:|---|---:|---|---|\n`
  for (const c of [...clubs].sort((a, b) => a.club.localeCompare(b.club))) {
    md += `| ${strength[c.club].name} | ${c.players.length} | ${c.lines.GK}/${c.lines.DEF}/${c.lines.MID}/${c.lines.ATT} | ${c.players.filter((p) => p.estimated).length} | ${fmtDate(c.as_of)} | [link](${c.source}) |\n`
  }
  md += `\n## Conflitos resolvidos\n\nQuando o mesmo jogador aparece em duas listas, fica no clube cuja lista é mais recente.\n\n`
  if (!report.conflicts.length) md += '_Nenhum._\n'
  else {
    md += `| Jogador | Ficou em | (data) | Removido de | (data) | Critério |\n|---|---|---|---|---|---|\n`
    for (const k of report.conflicts) md += `| ${k.name} | ${k.kept} | ${fmtDate(k.keptAsOf === UNKNOWN_DATE ? null : k.keptAsOf)} | ${k.dropped} | ${fmtDate(k.droppedAsOf === UNKNOWN_DATE ? null : k.droppedAsOf)} | ${k.why} |\n`
  }
  md += `\n## Avisos e dados ausentes\n\n`
  md += report.warnings.length ? report.warnings.map((w) => `- ${w}`).join('\n') + '\n' : '_Nenhum._\n'
  const stale = clubs.filter((c) => c.asOfSort < '2026-07-01')
  if (stale.length) md += `\n### Listas anteriores à janela do meio do ano (podem estar defasadas)\n\n${stale.map((c) => `- ${strength[c.club].name}: ${fmtDate(c.as_of)}`).join('\n')}\n`
  md += `\n### Campos sem fonte\n\n- **Idade / data de nascimento e pé preferido:** as fontes de elenco não trazem — ficam como desconhecidos (null).\n- **Nacionalidade:** desconhecida quando a fonte não informa (ex.: Universitario).\n- **Número da camisa:** "-" quando a fonte não informa (listas do canchallena).\n`
  for (const c of clubs.filter((c) => c.notes.length)) md += `- ${strength[c.club].name}: ${c.notes.join(' ')}\n`
  await writeFile(OUT_REPORT, md)

  console.log(`OK: ${clubs.length} clubes, ${players.length} jogadores, ${report.conflicts.length} conflitos, ${report.warnings.length} avisos`)
  console.log(`  -> ${path.relative(ROOT, OUT_JSON)}\n  -> ${path.relative(ROOT, OUT_REPORT)}\n  -> ${path.relative(ROOT, OUT_SQL)}`)
}

main().catch((e) => {
  console.error('ERRO:', e.message)
  process.exit(1)
})
