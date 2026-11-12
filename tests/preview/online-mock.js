// Prévia local do modo online: responde às chamadas on_* com dados fictícios, sem acessar o Supabase.
// Estado inicial pela URL: ?access=none | queued | unavailable | playing (padrão) e ?step=0..3 (craques já escolhidos).
// ?live=<segundos desde o pontapé> põe o próximo jogo em andamento (ex.: live=200 → minuto 28 no servidor).
import REAL_FORMATIONS from './formations.json'
const params = new URLSearchParams(window.location.search)
const state = { access: params.get('access') || 'playing', step: Number(params.get('step') ?? 0), name: 'FC davidcaua' }

const NAMES = ['FC davidcaua', 'FC Edson', 'FC Jeff', 'FC brunomartins', 'FC Dennis', 'Aurora FC', 'Real Maré', 'Estrela do Norte', 'União Serrana', 'Porto Vila', 'Ferroviário Central', 'Guarani do Vale']
const PAL = ['#e63946', '#1d3557', '#2a9d8f', '#f4a261', '#6a4c93', '#118ab2', '#ef476f', '#06d6a0', '#ffd166', '#8d99ae', '#bc6c25', '#3a86ff']
const PATTERNS = ['stripes', 'hoops', 'plain', 'sash', 'halves', 'chevron']
const clubs = NAMES.map((name, i) => ({ id: i + 1, name, short: name.replace(/^FC /, '').replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase(), colors: { a: PAL[i], b: i % 3 === 2 ? '#111827' : '#ffffff', pattern: PATTERNS[i % 6], shape: ['shield', 'round', 'shield', 'diamond'][i % 4], stadium: `Arena ${name.replace(/^FC /, '')}` }, bot: i > 4 }))
const myClub = () => ({ ...clubs[0], name: state.name, cash: 150000, reserved: 12000, debt: 0, draft_step: state.step, roster: players.length, strength: 71.4, levels: { stadium: 1, training: 2, medical: 0, youth: 0 } })

const SLOTS = ['09:00', '10:00', '11:00', '14:00', '15:30', '17:00']
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
const LIVE = params.get('live')
if (LIVE != null) {
  const f = fixtures.find((x) => x.status !== 'done' && (x.home === 1 || x.away === 1))
  f.kickoff = new Date(Date.now() - Number(LIVE) * 1000).toISOString()
}

const FIRST = ['Gabriel', 'Lucas', 'Matheus', 'Pedro', 'Rafael', 'João', 'Gustavo', 'Felipe', 'Vinícius', 'Kaique', 'Davi']
const LAST = ['Silva', 'Santos', 'Oliveira', 'Souza', 'Pereira', 'Lima', 'Carvalho', 'Ferreira', 'Rodrigues', 'Almeida', 'Costa', 'Gomes', 'Ribeiro']
const person = (n) => `${FIRST[n % FIRST.length]} ${LAST[(n * 7) % LAST.length]}`
const POS = ['GOL', 'LD', 'ZAG', 'ZAG', 'VOL', 'LE', 'PD', 'MC', 'ATA', 'MEI', 'PE', 'GOL', 'ZAG', 'LD', 'MC', 'LE', 'VOL', 'MEI', 'ATA']
const STAR_POS = ['ZAG', 'LD', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'ATA', 'PE']
const cardOf = (pos, ovr, k = 0) => {
  const off = { ATA: [-3, 5, -12, -11, -24, -5], ZAG: [-10, -30, -13, -11, 2, -3], GOL: [0, 1, -2, 2, -10, 0] }[pos] || [1, -9, 1, 1, -12, -5]
  return Object.fromEntries(['pac', 'sho', 'pas', 'dri', 'def', 'phy'].map((key, i) => [key, Math.max(20, Math.min(99, Math.round(ovr + off[i] + ((k * 7 + i * 3) % 5) - 2)))]))
}
const option = (step, idx) => {
  const pos = STAR_POS[step * 3 + idx - 1]
  const ovr = 78 + ((step * 2 + idx) % 5)
  return { idx, nat: ['BRA', 'ARG', 'FRA'][idx - 1], name: person(40 + step * 3 + idx), pos, age: 22 + ((step + idx) % 7), ovr, pot: 84 + idx, value: 30000 + idx * 9000, wage: 900 + idx * 150, card: cardOf(pos, ovr, idx) }
}
const picked = []
const players = POS.map((pos, i) => ({ id: `o${i + 1}`, name: person(i), pos, sec: [], age: 19 + (i % 13), ovr: 58 + ((i * 5) % 9), pot: 70 + (i % 9), cond: 100 - (i % 4) * 3, number: i + 1, wage: 180 + i * 7, contract_end: 2, star: false, g: [0, 0, 0, 0], injured: i === 16, value: 900 + i * 260 }))
for (let s = 0; s < state.step; s++) addStar(s, 1)
function addStar(step, idx) {
  const o = option(step, idx)
  const p = { id: `s${step}`, name: o.name, pos: o.pos, sec: [], age: o.age, ovr: o.ovr, pot: o.pot, cond: 100, number: 21 + step, wage: 900, contract_end: 3, star: true, g: [0, 0, 0, 0], injured: false, value: o.value }
  picked.push(p)
  players.push(p)
}

const FORMATIONS = REAL_FORMATIONS
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

// ---- partida ao vivo fictícia: mesmo relógio do banco (7 s por minuto, intervalo de 90 s) ----
const clockAt = (k, now) => {
  const x = (now - k) / 1000
  if (x < 0) return -1
  if (x < 315) return Math.floor(x / 7)
  if (x < 405) return 45
  if (x < 720) return 45 + Math.floor((x - 405) / 7)
  return 90
}
const rnd = (seed) => {
  let h = 2166136261
  for (const ch of String(seed)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619)
  return ((h >>> 0) % 10000) / 10000
}
const matches = new Map()
function oppSquad(club) {
  return POS.map((pos, i) => ({ id: `x${club}-${i}`, name: person(100 + club * 20 + i), pos, sec: [], age: 24, ovr: 60 + ((i + club) % 8), number: i + 1, cond: 100 }))
}
function openMatch(f) {
  if (matches.has(f.id)) return matches.get(f.id)
  const mineSide = f.home === 1 ? 'h' : 'a'
  const form = lineup?.formation || '4-3-3'
  const slotsOf = (fid) => (FORMATIONS.find((x) => x.id === fid) || FORMATIONS[0]).slots
  const list = []
  const add = (side, club, lu, pool) => {
    for (const s of slotsOf(lu.formation)) {
      const p = pool.find((x) => x.id === lu.slots[s.slot])
      list.push({ id: p.id, name: p.name, number: p.number, side, club_id: club, slot: s.slot, pos: s.pos, natural: p.pos, status: 'on', starter: true, fit: p.pos === s.pos ? 1 : 0.8, cond: 100, rating: 6, goals: 0, assists: 0, yellow: 0, red: 0, injured: false, minutes: 0, overall: Math.round(p.ovr), ovr: p.ovr })
    }
    for (const id of lu.bench) {
      const p = pool.find((x) => x.id === id)
      if (p) list.push({ id: p.id, name: p.name, number: p.number, side, club_id: club, slot: null, pos: p.pos, natural: p.pos, status: 'bench', starter: false, fit: 1, cond: 100, rating: 6, goals: 0, assists: 0, yellow: 0, red: 0, injured: false, minutes: 0, overall: Math.round(p.ovr), ovr: p.ovr })
    }
  }
  const oppId = mineSide === 'h' ? f.away : f.home
  const opp = oppSquad(oppId)
  const oppLu = { formation: '4-4-2', slots: {}, bench: [] }
  const used = new Set()
  for (const s of slotsOf('4-4-2')) {
    const p = opp.find((x) => !used.has(x.id) && x.pos === s.pos) || opp.find((x) => !used.has(x.id))
    used.add(p.id)
    oppLu.slots[s.slot] = p.id
  }
  oppLu.bench = opp.filter((p) => !used.has(p.id)).map((p) => p.id)
  if (mineSide === 'h') { add('h', f.home, lineup, players); add('a', f.away, oppLu, opp) } else { add('h', f.home, oppLu, opp); add('a', f.away, lineup, players) }
  const m = { f, mineSide, players: list, events: [], minute: 0, seq: 0, score: [0, 0], formation: mineSide === 'h' ? [form, '4-4-2'] : ['4-4-2', form], tactics: { h: {}, a: {} }, subs: { h: { used: 0, windows: 0 }, a: { used: 0, windows: 0 } }, poss: [0, 0] }
  matches.set(f.id, m)
  return m
}
function advance(m, now) {
  const target = clockAt(new Date(m.f.kickoff).getTime(), now)
  while (m.minute < target) {
    m.minute += 1
    const min = m.minute
    const side = rnd(`${m.f.id}:${min}:s`) < 0.5 ? 'h' : 'a'
    m.poss[side === 'h' ? 0 : 1] += 1
    const on = m.players.filter((p) => p.side === side && p.status === 'on' && p.pos !== 'GOL')
    const r = rnd(`${m.f.id}:${min}:r`)
    const who = on[Math.floor(rnd(`${m.f.id}:${min}:p`) * on.length)]
    const gk = m.players.find((p) => p.side !== side && p.pos === 'GOL' && p.status === 'on')
    const push = (kind, extra = {}) => m.events.push({ seq: ++m.seq, minute: min, side, kind, player: who?.id, player_name: who?.name, ...extra })
    if (r < 0.035) { m.score[side === 'h' ? 0 : 1] += 1; who.goals += 1; who.rating += 1; push('goal') }
    else if (r < 0.09) push('save', { player2: gk?.id, player2_name: gk?.name })
    else if (r < 0.15) push('shot_off')
    else if (r < 0.18) { who.yellow = 1; push('yellow') }
    else if (r < 0.2) push('offside')
    if (min === 45) m.events.push({ seq: ++m.seq, minute: 45, side: null, kind: 'ht' })
    for (const p of m.players) if (p.status === 'on') { p.cond = Math.max(40, p.cond - 0.45); p.minutes += 1 }
  }
  if (target >= 90 && !m.done) { m.done = true; m.events.push({ seq: ++m.seq, minute: 90, side: null, kind: 'ft' }); m.f.status = 'done'; m.f.hg = m.score[0]; m.f.ag = m.score[1] }
}
function payload(m, after) {
  const f = m.f
  return {
    server_now: new Date().toISOString(), fixture_id: f.id, kickoff: f.kickoff, comp: f.comp, round: f.round, stage: f.stage,
    status: new Date(f.kickoff).getTime() > Date.now() ? 'sched' : m.done ? 'finished' : 'live', minute: m.minute, my_side: m.mineSide,
    home: { ...clubs[f.home - 1], ...(f.home === 1 ? { name: state.name } : {}) }, away: { ...clubs[f.away - 1], ...(f.away === 1 ? { name: state.name } : {}) },
    present: { h: m.mineSide === 'h' || !clubs[f.home - 1].bot, a: m.mineSide === 'a' }, score: m.score, et: false, pens: null, decisive: false,
    tactics: m.tactics, formation: m.formation, subs: m.subs, max_subs: 5, max_windows: 3, fixes: [],
    events: m.events.filter((e) => e.seq > (after || 0)),
    stats: { poss: [Math.round((100 * m.poss[0]) / Math.max(1, m.poss[0] + m.poss[1])), 100 - Math.round((100 * m.poss[0]) / Math.max(1, m.poss[0] + m.poss[1]))], fouls: [3, 4], saves: [1, 2], corners: [2, 3], offsides: [1, 0] },
    players: m.players.map((p) => ({ ...p, cond: Math.round(p.cond) })), summary: m.done ? { home_goals: m.score[0], away_goals: m.score[1], motm: { name: m.players[9].name, rating: 7.8 } } : null,
  }
}
function poll({ p_fixture, p_after_seq }) {
  const f = p_fixture ? fixtures.find((x) => x.id === p_fixture) : fixtures.find((x) => x.status !== 'done' && (x.home === 1 || x.away === 1))
  if (new Date(f.kickoff).getTime() > Date.now() && !matches.has(f.id)) {
    const m = openMatch(f)
    return payload(m, p_after_seq)
  }
  const m = openMatch(f)
  advance(m, Date.now())
  return payload(m, p_after_seq)
}
function act({ p_fixture, p_changes }) {
  const m = matches.get(p_fixture)
  advance(m, Date.now())
  const sd = m.mineSide
  for (const s of p_changes.subs || []) {
    const o = m.players.find((p) => p.id === s.out)
    const i = m.players.find((p) => p.id === s.in)
    i.status = 'on'; i.slot = o.slot; i.pos = o.pos; o.status = 'off'; o.slot = null
    m.subs[sd].used += 1
    m.events.push({ seq: ++m.seq, minute: m.minute, side: sd, kind: 'sub', player: i.id, player_name: i.name, player2: o.id, player2_name: o.name })
  }
  if (p_changes.tactics) { m.tactics[sd] = p_changes.tactics; m.events.push({ seq: ++m.seq, minute: m.minute, side: sd, kind: 'tactic', detail: 'Ajuste tático' }) }
  if (p_changes.formation) m.formation[sd === 'h' ? 0 : 1] = p_changes.formation
  return { ...payload(m, 0), applied_at: m.minute }
}

// ---- clube fictício ----
const club = { used: 1, conv: 40, build: null, extra: 0 }
const clubState = () => ({ server_now: new Date().toISOString(), cash: 150000, reserved: 12000, debt: 0, levels: { stadium: 1, training: 2, medical: 0, youth: 0 }, build: club.build,
  costs: Object.fromEntries(['stadium', 'training', 'medical', 'youth'].map((k, i) => [k, { cost: 25000 * Math.round((([1, 2, 0, 0][i]) + 1) ** 1.5), time: (([1, 2, 0, 0][i]) + 1) * 43200 }])),
  train: { used: club.used, max: 3 + club.extra, cond_cost: 6, extra: club.extra, extra_max: 5, extra_cost: 40 }, coins: { wallet: 820, converted: club.conv, cap: 1000, rate: 1000 }, match_today: true, wages: 6900 })

// ---- mercado fictício ----
const lots = Array.from({ length: 7 }, (_, i) => {
  const ovr = i < 3 ? [84, 74, 66][i] : 62 + ((i * 7) % 20)
  const opens = Date.now() - 60000 + (i > 4 ? (i - 4) * 2400000 : 0)
  return { id: 100 + i, status: 'open', opens_at: new Date(opens).toISOString(), ends_at: new Date(Date.now() + [45, 200, 420, 90, 600, 2400, 4800][i] * 1000).toISOString(),
    start_price: 4000 + i * 1500, best_bid: i % 2 ? 6000 + i * 2000 : null, bids: i % 2 ? 3 : 0, min_bid: i % 2 ? 6300 + i * 2100 : 4000 + i * 1500, mine: false, leading: i === 3 || i === 1, featured: i < 3 ? i + 1 : 0, bidding: i === 1 || i === 3 || i === 0, bidders: i % 2 ? 3 : i === 0 ? 2 : 0,
    history: i % 2 || i === 0 ? [{ club: clubs[i === 0 ? 6 : 0], amount: 6000 + i * 2000, me: i !== 0 }, { club: clubs[4], amount: 5600 + i * 1900, me: false }, { club: clubs[0], amount: 5000 + i * 1800, me: true }] : [],
    player: { id: `m${i}`, name: person(70 + i), pos: STAR_POS[(i * 4) % 9], sec: [], age: 19 + i * 2, ovr, pot: ovr + 6, star: ovr >= 80, cond: 100, wage: 300, value: 9000 + i * 7000, number: null, card: cardOf(STAR_POS[(i * 4) % 9], ovr, i) },
    seller: i === 4 ? clubs[2] : null, best_club: i % 2 ? (i === 3 ? clubs[0] : clubs[6]) : null }
})
lots[0].best_bid = 31000; lots[0].best_club = clubs[6]; lots[0].min_bid = 32600; lots[0].start_price = 28000
const market = () => ({ server_now: new Date().toISOString(), my_club: 1, club: { cash: 30000, reserved: 12000, debt: 0, roster: players.length }, coins: { wallet: 820, rate: 1000, bid_rate: 600, converted: 40, cap: 1000 }, lots, recent: lots.slice(0, 3).map((l) => ({ ...l, status: 'sold', best_bid: 8000, best_club: clubs[5], seller: null })) })

const prepState = { scout: false, talk: null }
const status = () => {
  const playing = state.access === 'playing'
  const next = fixtures.find((f) => f.status !== 'done' && (f.home === 1 || f.away === 1))
  return {
    server_now: new Date().toISOString(), access: state.access,
    season: state.access === 'none' && params.get('season') === '0' ? null : { id: 1, kind: params.get('kind') || 'main', starts_on: start.toISOString().slice(0, 10) },
    club: playing ? myClub() : null,
    position: 3,
    coins: 820,
    day: { n: 3, of: 26 },
    standing: { p: 2, w: 1, d: 1, l: 0, gf: 4, ga: 2, pts: 4 },
    form: ['W', 'D'],
    train: { used: 1, max: 3 },
    prep: playing ? { fixture: 1, score: (prepState.scout ? 20 : 0) + (prepState.talk ? 20 : 0) + 30 + 15, bonus: (((prepState.scout ? 20 : 0) + (prepState.talk ? 20 : 0) + 45) * 0.03).toFixed(2), lineup: true, train: 1, train_max: 2, scout: prepState.scout, talk: prepState.talk, streak: 3, best: 4, coins: 5, streak_every: 5, streak_coins: 30 } : null,
    featured: { count: 3, ends_at: new Date(Date.now() + 1380000).toISOString() },
    bids: playing ? [lots[1], lots[0]] : [],
    results: playing && !state.seen && params.get('result') ? [{ id: 1, text: '', at: new Date().toISOString(), data: { lot: 1, won: params.get('result') === 'won', price: 48200, player: { id: 'x', name: person(77), pos: 'ATA', ovr: 83, age: 24, star: true }, winner: params.get('result') === 'won' ? myClub() : clubs[3] } }] : [],
    news: [{ id: 5, kind: 'market', text: 'Rafael Santos foi vendido por $ 6.500.', at: new Date().toISOString() }, { id: 4, kind: 'build', text: 'Obra concluída: a estrutura do clube subiu de nível.', at: new Date().toISOString() }],
    next: playing && next ? { id: next.id, comp: next.comp, round: next.round, kickoff: next.kickoff, status: next.status, live: new Date(next.kickoff) <= new Date(), at_home: next.home === 1, opp: clubs[(next.home === 1 ? next.away : next.home) - 1] } : null,
    last: (() => {
      const l = [...fixtures].reverse().find((f) => f.status === 'done' && (f.home === 1 || f.away === 1))
      return playing && l ? { id: l.id, hg: l.hg, ag: l.ag, at_home: l.home === 1, opp: clubs[(l.home === 1 ? l.away : l.home) - 1] } : null
    })(),
  }
}
const draft = () => ({ club: myClub(), step: state.step, done: state.step >= 3, line: ['DEF', 'MID', 'ATT'][state.step] ?? null, options: state.step >= 3 ? [] : [1, 2, 3].map((i) => option(state.step, i)), picked })
const squad = () => {
  const next = fixtures.find((f) => f.status !== 'done' && (f.home === 1 || f.away === 1))
  return { club: myClub(), live_fixture: next && new Date(next.kickoff) <= new Date() ? next.id : null, players: [...players].sort((a, b) => b.ovr - a.ovr).map((p, i) => ({ ...p, rhythm: 60, yellows: i === 3 ? 2 : 0, suspended: i === 5, xp: [10, 40, 70, 25], nat: ['BRA', 'ARG', 'URU', 'ESP'][i % 4], sell: Math.round(p.value * 0.6), card: cardOf(p.pos, p.ovr, i) })), lineup: lineup && { roles: {}, ...lineup } }
}
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
  on_lineup_save: ({ p_formation, p_slots, p_bench, p_tactics }) => { lineup = { ...lineup, formation: p_formation, slots: p_slots, bench: p_bench, tactics: p_tactics || lineup.tactics }; return squad() },
  on_lineup_auto: ({ p_formation }) => { autoLineup(p_formation || lineup?.formation); return squad() },
  on_club_identity: ({ p }) => {
    if (p.name) state.name = p.name
    if (p.short) clubs[0].short = p.short
    clubs[0].colors = { ...clubs[0].colors, ...Object.fromEntries(Object.entries(p).filter(([k]) => ['a', 'b', 'pattern', 'shape', 'stadium'].includes(k))) }
    return status()
  },
  on_scout: () => { prepState.scout = true; return { fixture: 1, opp: { ...clubs[3], position: 4, formation: '4-4-2', style: 'attacking', form: ['W', 'L', 'W'], stars: [0, 1, 2].map((i) => ({ id: `st${i}`, name: person(90 + i), pos: ['ATA', 'MC', 'ZAG'][i], nat: 'ARG', ovr: 80 - i * 2, age: 26, star: i === 0, card: cardOf(['ATA', 'MC', 'ZAG'][i], 80 - i * 2, i) })) }, sectors: { me: { GK: 60, DEF: 68.2, MID: 70.4, ATT: 66 }, opp: { GK: 64, DEF: 66, MID: 67.5, ATT: 71.2 } } } },
  on_team_talk: ({ p_talk }) => { prepState.talk = p_talk; return {} },
  on_news_seen: () => { state.seen = true; return null },
  on_club_rename: ({ p_name }) => {
    if (p_name.trim().length < 3) return { error: 'O nome do clube precisa ter de 3 a 24 caracteres' }
    state.name = p_name.trim()
    return status()
  },
  on_calendar: () => ({ server_now: new Date().toISOString(), my_club: 1, clubs, fixtures }),
  on_standings: table,
  on_match_poll: poll,
  on_market: market,
  on_bid: ({ p_lot, p_amount }) => {
    const l = lots.find((x) => x.id === p_lot)
    if (p_amount < l.min_bid) return { error: `O lance mínimo agora é $ ${l.min_bid}` }
    Object.assign(l, { best_bid: p_amount, best_club: clubs[0], leading: true, bids: l.bids + 1, min_bid: Math.round(p_amount * 1.05) })
    return market()
  },
  on_lot_create: ({ p_player, p_price }) => {
    const p = players.find((x) => x.id === p_player)
    lots.unshift({ id: Date.now(), status: 'open', opens_at: new Date().toISOString(), ends_at: new Date(Date.now() + 600000).toISOString(), start_price: p_price, best_bid: null, bids: 0, min_bid: p_price, mine: true, leading: false, player: { ...p, value: p.value }, seller: clubs[0], best_club: null })
    return market()
  },
  on_lot_cancel: ({ p_lot }) => { lots.splice(lots.findIndex((x) => x.id === p_lot), 1); return market() },
  on_club: () => clubState(),
  on_cup: () => {
    const pair = (r, i, a, b, done) => ({ round: r, stage: ['r1', 'qf', 'sf', 'final'][r - 1], id: 900 + r * 10 + i, kickoff: new Date(Date.now() - 86400e3 * (5 - r)).toISOString(), status: done ? 'done' : 'sched', hg: done ? (a + b) % 3 : null, ag: done ? (a * b) % 3 : null, pens: done && (a + b) % 3 === (a * b) % 3 ? [4, 3] : null, home: clubs[a], away: clubs[b], winner: done ? clubs[(a + b) % 3 === (a * b) % 3 || (a + b) % 3 > (a * b) % 3 ? a : b].id : null })
    return { my_club: 1, byes: [clubs[0], clubs[3], clubs[7], clubs[9]], rounds: [pair(1, 0, 4, 11, true), pair(1, 1, 5, 10, true), pair(1, 2, 6, 2, true), pair(1, 3, 8, 1, true), pair(2, 0, 0, 4, false), pair(2, 1, 3, 10, false), pair(2, 2, 7, 6, false), pair(2, 3, 9, 1, false)], history: [{ season: 0, champion: 'Aurora FC', cup: 'Real Maré', me: { pos: 3, pts: 41, cup: 'sf' } }] }
  },
  on_build: ({ p_kind }) => { club.build = { kind: p_kind, until: new Date(Date.now() + 3600e3 * 12).toISOString() }; return clubState() },
  on_train_start: ({ p_game }) => { club.used += 1; return { session: 1, game: p_game, seed: 'x', started_at: new Date().toISOString() } },
  on_train_finish: ({ p_score }) => ({ score: p_score, group: 3, players: players.slice(0, 3).map((p, i) => ({ id: p.id, name: p.name, pos: p.pos, gain: Math.round(p_score * 40), before: p.ovr, ovr: p.ovr + (i === 0 ? 0.5 : 0), xp: 20 })) }),
  on_renew: () => squad(),
  online_train_energy_buy: () => { club.extra += 1; return clubState() },
  on_sell: ({ p_player }) => { players.splice(players.findIndex((x) => x.id === p_player), 1); return squad() },
  online_coins_convert: ({ p_coins }) => { club.conv += p_coins; return clubState() },
  on_finance: () => ({ cash: 150000, reserved: 12000, debt: 0, wages: players.reduce((a, p) => a + p.wage, 0), ledger: [{ kind: 'gate', amount: 8200, note: 'Bilheteria', at: new Date().toISOString() }, { kind: 'wage', amount: -5400, note: 'Salários do dia', at: new Date().toISOString() }], news: [{ kind: 'market', text: 'Rafael Santos foi vendido por $ 6.500.', at: new Date().toISOString() }] }),
  on_match_act: act,
  on_roles_save: ({ p_roles }) => { lineup = { ...lineup, roles: p_roles }; return squad() },
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
