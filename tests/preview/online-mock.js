// Prévia local do modo online: responde às chamadas on_* com dados fictícios, sem acessar o Supabase.
// Estado inicial pela URL: ?access=none | queued | unavailable | playing (padrão) e ?step=0..3 (craques já escolhidos).
const params = new URLSearchParams(window.location.search)
const state = { access: params.get('access') || 'playing', step: Number(params.get('step') ?? 0), name: 'FC davidcaua' }

const NAMES = ['FC davidcaua', 'FC Edson', 'FC Jeff', 'FC brunomartins', 'FC Dennis', 'Aurora FC', 'Real Maré', 'Estrela do Norte', 'União Serrana', 'Porto Vila', 'Ferroviário Central', 'Guarani do Vale']
const PAL = ['#e63946', '#1d3557', '#2a9d8f', '#f4a261', '#6a4c93', '#118ab2', '#ef476f', '#06d6a0', '#ffd166', '#8d99ae', '#bc6c25', '#3a86ff']
const clubs = NAMES.map((name, i) => ({ id: i + 1, name, short: name.replace(/^FC /, '').replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase(), colors: { a: PAL[i], b: i % 3 === 2 ? '#111827' : '#ffffff' }, bot: i > 4 }))
const myClub = () => ({ ...clubs[0], name: state.name, cash: 150000, reserved: 12000, draft_step: state.step })

const SLOTS = ['16:00', '17:30', '19:00', '20:00', '21:00', '22:00']
const start = new Date()
start.setHours(0, 0, 0, 0)
const fixtures = []
for (let leg = 0; leg < 2; leg++) for (let r = 0; r < 11; r++) for (let i = 0; i < 6; i++) {
  const a = i === 0 ? 11 : (r + i) % 11
  const b = i === 0 ? r : (r - i + 11) % 11
  const flip = ((r + i) % 2 === 0) === (leg === 0)
  const round = r + 1 + leg * 11
  const day = round + Math.floor((round - 1) / 5) - 2 // a primeira rodada foi ontem
  const [h, m] = SLOTS[(i + round) % 6].split(':').map(Number)
  const kickoff = new Date(start.getTime() + day * 86400000 + (h * 60 + m) * 60000)
  const done = kickoff.getTime() + 12 * 60000 < Date.now()
  fixtures.push({ id: fixtures.length + 1, comp: 'L', round, stage: null, home: (flip ? a : b) + 1, away: (flip ? b : a) + 1, kickoff: kickoff.toISOString(), status: done ? 'done' : 'sched', hg: done ? (a + round) % 4 : null, ag: done ? (b + round) % 3 : null, pens: null })
}
fixtures.sort((x, y) => x.kickoff.localeCompare(y.kickoff))

const FIRST = ['Gabriel', 'Lucas', 'Matheus', 'Pedro', 'Rafael', 'João', 'Gustavo', 'Felipe', 'Vinícius', 'Kaique', 'Davi']
const LAST = ['Silva', 'Santos', 'Oliveira', 'Souza', 'Pereira', 'Lima', 'Carvalho', 'Ferreira', 'Rodrigues', 'Almeida', 'Costa', 'Gomes', 'Ribeiro']
const person = (n) => `${FIRST[n % FIRST.length]} ${LAST[(n * 7) % LAST.length]}`
const POS = ['GOL', 'LD', 'ZAG', 'ZAG', 'VOL', 'LE', 'PD', 'MC', 'ATA', 'MEI', 'PE', 'GOL', 'ZAG', 'LD', 'MC', 'LE', 'VOL', 'MEI', 'ATA']
const STAR_POS = ['ZAG', 'LD', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'ATA', 'PE']
const option = (step, idx) => ({ idx, name: person(40 + step * 3 + idx), pos: STAR_POS[step * 3 + idx - 1], age: 22 + ((step + idx) % 7), ovr: 78 + ((step * 2 + idx) % 5), pot: 84 + idx, value: 30000 + idx * 9000 })
const picked = []
const players = POS.map((pos, i) => ({ id: `o${i + 1}`, name: person(i), pos, sec: [], age: 19 + (i % 13), ovr: 58 + ((i * 5) % 9), pot: 70 + (i % 9), cond: 100 - (i % 4) * 3, number: i + 1, wage: 180 + i * 7, contract_end: 2, star: false, g: [0, 0, 0, 0], injured: i === 16, value: 900 + i * 260 }))
for (let s = 0; s < state.step; s++) addStar(s, 1)
function addStar(step, idx) {
  const o = option(step, idx)
  const p = { id: `s${step}`, name: o.name, pos: o.pos, sec: [], age: o.age, ovr: o.ovr, pot: o.pot, cond: 100, number: 21 + step, wage: 900, contract_end: 3, star: true, g: [0, 0, 0, 0], injured: false, value: o.value }
  picked.push(p)
  players.push(p)
}

const FORMATIONS = [
  { id: '4-3-3', name: '4-3-3', slots: ['GOL:GOL', 'LD:LD', 'ZAG1:ZAG', 'ZAG2:ZAG', 'LE:LE', 'VOL:VOL', 'MC1:MC', 'MC2:MC', 'PD:PD', 'ATA:ATA', 'PE:PE'] },
  { id: '4-4-2', name: '4-4-2', slots: ['GOL:GOL', 'LD:LD', 'ZAG1:ZAG', 'ZAG2:ZAG', 'LE:LE', 'MD:PD', 'MC1:MC', 'MC2:MC', 'ME:PE', 'ATA1:ATA', 'ATA2:ATA'] },
].map((f) => ({ ...f, slots: f.slots.map((s) => ({ slot: s.split(':')[0], pos: s.split(':')[1] })) }))
let lineup = null
function autoLineup(formation) {
  const f = FORMATIONS.find((x) => x.id === formation) || FORMATIONS[0]
  const used = new Set()
  const slots = {}
  for (const s of f.slots) {
    const best = players.filter((p) => !used.has(p.id)).sort((a, b) => (b.pos === s.pos) - (a.pos === s.pos) || b.ovr - a.ovr)[0]
    used.add(best.id)
    slots[s.slot] = best.id
  }
  lineup = { formation: f.id, slots, bench: players.filter((p) => !used.has(p.id)).sort((a, b) => b.ovr - a.ovr).slice(0, 12).map((p) => p.id), tactics: {} }
}
if (state.step >= 3) autoLineup()

const status = () => {
  const playing = state.access === 'playing'
  const next = fixtures.find((f) => f.status !== 'done' && (f.home === 1 || f.away === 1))
  return {
    server_now: new Date().toISOString(), access: state.access,
    season: state.access === 'none' && params.get('season') === '0' ? null : { id: 1, kind: params.get('kind') || 'main', starts_on: start.toISOString().slice(0, 10) },
    club: playing ? myClub() : null,
    next: playing && next ? { id: next.id, comp: next.comp, round: next.round, kickoff: next.kickoff, status: next.status, at_home: next.home === 1, opp: clubs[(next.home === 1 ? next.away : next.home) - 1] } : null,
  }
}
const draft = () => ({ step: state.step, done: state.step >= 3, line: ['DEF', 'MID', 'ATT'][state.step] ?? null, options: state.step >= 3 ? [] : [1, 2, 3].map((i) => option(state.step, i)), picked })
const squad = () => ({ club: myClub(), players: [...players].sort((a, b) => b.ovr - a.ovr), lineup })
const table = () => ({ my_club: 1, rows: clubs.map((c, i) => ({ club_id: c.id, ...c, p: 2, w: (i * 3) % 3, d: i % 2, l: 0, gf: 5 - (i % 4), ga: i % 3, pts: ((i * 3) % 3) * 3 + (i % 2) })).sort((a, b) => b.pts - a.pts) })

const RPC = {
  on_status: status,
  on_join_queue: () => { state.access = 'queued'; return status() },
  on_draft_read: draft,
  on_draft_pick: ({ p_step, p_idx }) => {
    if (p_step === state.step && state.step < 3) {
      addStar(state.step, p_idx)
      state.step += 1
      if (state.step === 3) autoLineup()
    }
    return draft()
  },
  on_squad: squad,
  on_lineup_save: ({ p_formation, p_slots, p_bench }) => { lineup = { ...lineup, formation: p_formation, slots: p_slots, bench: p_bench }; return squad() },
  on_lineup_auto: ({ p_formation }) => { autoLineup(p_formation || lineup?.formation); return squad() },
  on_club_rename: ({ p_name }) => {
    if (p_name.trim().length < 3) return { error: 'O nome do clube precisa ter de 3 a 24 caracteres' }
    state.name = p_name.trim()
    return status()
  },
  on_calendar: () => ({ server_now: new Date().toISOString(), my_club: 1, clubs, fixtures }),
  on_standings: table,
}

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const realFetch = window.fetch.bind(window)
window.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, window.location.href)
  if (!url.pathname.startsWith('/rest/v1/') && !url.pathname.startsWith('/auth/v1/')) return realFetch(input, init)
  await new Promise((r) => setTimeout(r, 120))
  if (url.pathname.endsWith('/sim_formations')) return json(FORMATIONS)
  const fn = url.pathname.split('/rpc/')[1]
  if (fn === 'on_status' && state.access === 'unavailable') return json({ code: 'PGRST202', message: 'função não encontrada' }, 404)
  if (!RPC[fn]) return json(null)
  const out = RPC[fn](init?.body ? JSON.parse(init.body) : {})
  return out?.error ? json({ code: 'P0001', message: out.error }, 400) : json(out)
}
