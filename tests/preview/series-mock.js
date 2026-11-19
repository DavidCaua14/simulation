// Prévia das séries (fase 35): 94 clubes reais em A/B/C/D, o clube do técnico no Grupo 1 da D, calendário com dois
// jogos por dia (manhã e tarde), tabelas, rodadas e copa. Mesmos formatos das RPCs on_standings, on_round, on_calendar e on_cup.
const NAMES = {
  A: ['Athletico-PR', 'Atlético-MG', 'Bahia', 'Botafogo', 'Chapecoense', 'Corinthians', 'Coritiba', 'Cruzeiro', 'Flamengo', 'Fluminense', 'Grêmio', 'Internacional', 'Mirassol', 'Palmeiras', 'Red Bull Bragantino', 'Remo', 'Santos', 'São Paulo', 'Vasco da Gama', 'Vitória'],
  B: ['América-MG', 'Athletic', 'Atlético-GO', 'Avaí', 'Botafogo-SP', 'Ceará', 'CRB', 'Criciúma', 'Cuiabá', 'Fortaleza', 'Goiás', 'Juventude', 'Londrina', 'Náutico', 'Novorizontino', 'Operário-PR', 'Ponte Preta', 'São Bernardo', 'Sport', 'Vila Nova'],
  C: ['Maringá', 'Ferroviária', 'Inter de Limeira', 'Santa Cruz', 'Amazonas', 'Anápolis', 'Barra', 'Botafogo-PB', 'Brusque', 'Caxias', 'Figueirense', 'Floresta', 'Guarani', 'Ituano', 'Maranhão', 'Paysandu', 'Volta Redonda', 'Ypiranga', 'Uberlândia', 'ASA', 'ABC', 'Gama', 'Goiatuba', 'Nacional-AM'],
  D: ['FC davidcaua', 'FC Edson', 'FC Jeff', 'FC brunomartins', 'Itabaiana', 'Confiança', 'Sergipe', 'Treze', 'Campinense', 'América-RN', 'Ferroviário', 'Moto Club', 'Fluminense-PI', 'Altos', 'Juazeirense', 'Jacuipense', 'Brasiliense', 'Portuguesa', 'XV de Piracicaba', 'Joinville', 'São José-RS', 'Atlético de Alagoinhas', 'Velo Clube', 'Noroeste', 'Água Santa', 'CRAC', 'Democrata-GV', 'Cianorte', 'Decisão', 'Madureira'],
}
const PAL = [['#C8102E', '#111111'], ['#111111', '#FFFFFF'], ['#0057B8', '#E31B23'], ['#006437', '#FFFFFF'], ['#0033A0', '#FFFFFF'], ['#8B1E3F', '#0A7A3D'], ['#FFD100', '#111111'], ['#1E40AF', '#FFFFFF'], ['#E30613', '#FFFFFF'], ['#0F7A3A', '#FFFFFF'], ['#7A1F2B', '#FFFFFF'], ['#5BA4E6', '#FFFFFF']]
const PAT = ['stripes', 'hoops', 'plain', 'sash', 'halves', 'chevron']
let id = 0
// escudo oficial de cada clube real (como em on_clubs.colors.crest)
const CREST = {"Athletico-PR": "crests/athletico-pr.svg", "Atlético-MG": "crests/atletico-mg.svg", "Bahia": "crests/bahia.svg", "Botafogo": "crests/botafogo.svg", "Chapecoense": "crests/chapecoense.svg", "Corinthians": "crests/corinthians.svg", "Coritiba": "crests/coritiba.svg", "Cruzeiro": "crests/cruzeiro.svg", "Flamengo": "crests/flamengo.svg", "Fluminense": "crests/fluminense.svg", "Grêmio": "crests/gremio.svg", "Internacional": "crests/internacional.svg", "Mirassol": "crests/mirassol.svg", "Palmeiras": "crests/palmeiras.svg", "Red Bull Bragantino": "crests/bragantino.svg", "Remo": "crests/remo.svg", "Santos": "crests/santos.svg", "São Paulo": "crests/sao-paulo.svg", "Vasco da Gama": "crests/vasco.svg", "Vitória": "crests/vitoria.svg", "América-MG": "crests/america-mg.svg", "Athletic": "crests/athletic-mg.svg", "Atlético-GO": "crests/atletico-go.svg", "Avaí": "crests/avai.svg", "Botafogo-SP": "crests/botafogo-sp.svg", "Ceará": "crests/ceara.svg", "CRB": "crests/crb.svg", "Criciúma": "crests/criciuma.svg", "Cuiabá": "crests/cuiaba.svg", "Fortaleza": "crests/fortaleza.svg", "Goiás": "crests/goias.svg", "Juventude": "crests/juventude.svg", "Londrina": "crests/londrina.svg", "Náutico": "crests/nautico.svg", "Novorizontino": "crests/novorizontino.svg", "Operário-PR": "crests/operario-pr.svg", "Ponte Preta": "crests/ponte-preta.svg", "São Bernardo": "crests/sao-bernardo.svg", "Sport": "crests/sport.svg", "Vila Nova": "crests/vila-nova.svg", "Maringá": "crests/online/maringa.webp", "Ferroviária": "crests/online/ferroviaria.webp", "Inter de Limeira": "crests/online/inter-limeira.webp", "Santa Cruz": "crests/online/santa-cruz.webp", "Amazonas": "crests/online/amazonas.webp", "Anápolis": "crests/online/anapolis.webp", "Barra": "crests/online/barra.webp", "Botafogo-PB": "crests/online/botafogo-pb.webp", "Brusque": "crests/online/brusque.webp", "Caxias": "crests/online/caxias.webp", "Figueirense": "crests/online/figueirense.webp", "Floresta": "crests/online/floresta.webp", "Guarani": "crests/online/guarani.webp", "Ituano": "crests/online/ituano.webp", "Maranhão": "crests/online/maranhao.webp", "Paysandu": "crests/online/paysandu.webp", "Volta Redonda": "crests/online/volta-redonda.webp", "Ypiranga": "crests/online/ypiranga-rs.webp", "Uberlândia": "crests/online/uberlandia.webp", "ASA": "crests/online/asa.webp", "ABC": "crests/online/abc.webp", "Gama": "crests/online/gama.webp", "Goiatuba": "crests/online/goiatuba.webp", "Nacional-AM": "crests/online/nacional-am.webp", "Itabaiana": "crests/online/itabaiana.webp", "Confiança": "crests/online/confianca.webp", "Sergipe": "crests/online/sergipe.webp", "Treze": "crests/online/treze.webp", "Campinense": "crests/online/campinense.webp", "América-RN": "crests/online/america-rn.webp", "Ferroviário": "crests/online/ferroviario.webp", "Moto Club": "crests/online/moto-club.webp", "Fluminense-PI": "crests/online/fluminense-pi.webp", "Altos": "crests/online/altos.webp", "Juazeirense": "crests/online/juazeirense.webp", "Jacuipense": "crests/online/jacuipense.webp", "Brasiliense": "crests/online/brasiliense.webp", "Portuguesa": "crests/online/portuguesa.webp", "XV de Piracicaba": "crests/online/xv-piracicaba.webp", "Joinville": "crests/online/joinville.webp", "São José-RS": "crests/online/sao-jose-rs.webp", "Atlético de Alagoinhas": "crests/online/atletico-alagoinhas.webp", "Velo Clube": "crests/online/velo-clube.webp", "Noroeste": "crests/online/noroeste.webp", "Água Santa": "crests/online/agua-santa.webp", "CRAC": "crests/online/crac.webp", "Democrata-GV": "crests/online/democrata-gv.webp", "Cianorte": "crests/online/cianorte.webp", "Decisão": "crests/online/decisao.webp", "Madureira": "crests/online/madureira.webp", "America-RJ": "crests/online/america-rj.webp", "Maricá": "crests/online/marica.webp", "São Luiz": "crests/online/sao-luiz.webp", "Marcílio Dias": "crests/online/marcilio-dias.webp"}
export const CLUBS = []
for (const div of ['A', 'B', 'C', 'D']) {
  NAMES[div].forEach((name, i) => {
    id += 1
    const [a, b] = PAL[(id * 5) % PAL.length]
    CLUBS.push({
      id, name, div, bot: !name.startsWith('FC '), short: name.replace(/^FC /, '').replace(/[^A-Za-zÀ-ú]/g, '').slice(0, 3).toUpperCase(),
      colors: { a, b, pattern: PAT[id % 6], shape: 'shield', stadium: `Estádio ${name}`, ...(CREST[name] ? { crest: CREST[name] } : {}) }, grp: div === 'D' ? (i % 4 === 0 || i % 4 === 3 ? 1 : 2) : 0,
    })
  })
}
export const ME = CLUBS.find((c) => c.name === 'FC davidcaua')
const byId = new Map(CLUBS.map((c) => [c.id, c]))
const club = (c) => ({ id: c.id, name: c.name, short: c.short, colors: c.colors, bot: c.bot, div: c.div, crest: null })

// mesmo plano de turnos do banco: 51 turnos, copa nos turnos 3, 8, 13, 18, 22, 27, 31, 36, 40, 45 e 49
const CUP_SLOTS = [3, 8, 13, 18, 22, 27, 31, 36, 40, 45, 49]
const LG = Array.from({ length: 51 }, (_, i) => i).filter((i) => !CUP_SLOTS.includes(i))
const AM = ['08:00', '09:30', '10:30', '08:30', '10:00', '09:00', '10:15']
const PM = ['14:00', '15:30', '13:00', '15:00', '14:30', '13:30', '15:15']
const OFF = { A: 0, B: 5, C: 10, D: 15, K: 0 }
const START = new Date()
START.setHours(0, 0, 0, 0)
START.setDate(START.getDate() - 6) // temporada começou há 6 dias
const kick = (slot, div) => {
  const day = Math.floor(slot / 2)
  const [h, m] = (slot % 2 === 0 ? AM : PM)[day % 7].split(':').map(Number)
  return new Date(START.getTime() + day * 864e5 + (h * 60 + m + OFF[div]) * 6e4)
}
const roundSlot = (div, r) => (div === 'K' ? CUP_SLOTS[r - 1] : LG[div === 'C' ? Math.round(((r - 1) * 39) / 30) : div === 'D' ? Math.round(((r - 1) * 39) / 35) : r - 1])

// rodízio (método do círculo), igual a on_rr
function rr(ids, double) {
  const a = ids.length % 2 ? [...ids, 0] : [...ids]
  const m = a.length
  const out = []
  for (let r = 0; r < m - 1; r++) for (let i = 0; i < m / 2; i++) {
    const x = i === 0 ? m - 1 : (r + i) % (m - 1)
    const y = i === 0 ? r : (r - i + m - 1) % (m - 1)
    const [h, w] = (r + i) % 2 === 0 ? [a[x], a[y]] : [a[y], a[x]]
    if (!h || !w) continue
    out.push({ rnd: r + 1, home: h, away: w })
    if (double) out.push({ rnd: r + m, home: w, away: h })
  }
  return out
}
const hash = (n) => ((Math.sin(n * 12.9898) * 43758.5453) % 1 + 1) % 1
let fid = 0
export const FIXTURES = []
for (const div of ['A', 'B', 'C', 'D']) {
  for (const g of div === 'D' ? [1, 2] : [0]) {
    const ids = CLUBS.filter((c) => c.div === div && c.grp === g).map((c) => c.id)
    for (const x of rr(ids, div !== 'C')) {
      const slot = roundSlot(div, x.rnd)
      const k = kick(slot, div)
      const done = k.getTime() + 100 * 6e4 < Date.now()
      const s = hash(++fid)
      FIXTURES.push({ id: fid, comp: 'L', div, round: x.rnd, stage: null, leg: null, grp: g || null, home: x.home, away: x.away, kickoff: k.toISOString(), slot,
        status: done ? 'done' : 'sched', hg: done ? Math.floor(s * 4) : null, ag: done ? Math.floor(hash(fid + 7) * 3) : null, pens: null })
    }
  }
}
// copa: 1ª fase (C, D e 6 piores da B) e 2ª fase sorteada
const cup1 = [...CLUBS.filter((c) => c.div === 'D' || c.div === 'C'), ...CLUBS.filter((c) => c.div === 'B').slice(14)]
for (let i = 0; i < cup1.length; i += 2) {
  const [h, a] = cup1[i].div > cup1[i + 1].div ? [cup1[i], cup1[i + 1]] : [cup1[i + 1], cup1[i]]
  const k = kick(CUP_SLOTS[0], h.div)
  const hg = Math.floor(hash(i) * 3), ag = Math.floor(hash(i + 3) * 3)
  FIXTURES.push({ id: ++fid, comp: 'C', div: null, round: 1, stage: 'f1', leg: null, tie: 100 + i / 2, home: h.id, away: a.id, kickoff: k.toISOString(), slot: CUP_SLOTS[0], status: 'done', hg, ag, pens: hg === ag ? [4, 2] : null })
}
// o clube do técnico na copa: garante que passou e está na 2ª fase
const myCup = FIXTURES.find((f) => f.comp === 'C' && f.round === 1 && (f.home === ME.id || f.away === ME.id))
if (myCup) Object.assign(myCup, myCup.home === ME.id ? { hg: 2, ag: 1, pens: null } : { hg: 0, ag: 1, pens: null })
const cupWinner = (f) => (f.hg > f.ag || (f.hg === f.ag && f.pens?.[0] > f.pens?.[1]) ? f.home : f.away)
const r2 = [...FIXTURES.filter((f) => f.comp === 'C').map(cupWinner), ...CLUBS.filter((c) => c.div === 'A' || (c.div === 'B' && !cup1.includes(c))).map((c) => c.id)]
for (let i = 0; i < r2.length; i += 2) {
  const k = kick(CUP_SLOTS[1], byId.get(r2[i]).div)
  FIXTURES.push({ id: ++fid, comp: 'C', div: null, round: 2, stage: 'f2', leg: null, tie: 200 + i / 2, home: r2[i], away: r2[i + 1], kickoff: k.toISOString(), slot: CUP_SLOTS[1], status: 'sched', hg: null, ag: null, pens: null })
}

const LIVE = new URLSearchParams(window.location.search).get('live')
if (LIVE != null) {
  const f = FIXTURES.filter((x) => x.status !== 'done' && (x.home === ME.id || x.away === ME.id)).sort((a, b) => a.kickoff.localeCompare(b.kickoff))[0]
  if (f) f.kickoff = new Date(Date.now() - Number(LIVE) * 1000).toISOString()
}
const mineList = () => FIXTURES.filter((f) => f.home === ME.id || f.away === ME.id).sort((a, b) => a.kickoff.localeCompare(b.kickoff))

function tableOf(div, grp) {
  const rows = new Map(CLUBS.filter((c) => c.div === div && c.grp === grp).map((c) => [c.id, { ...club(c), p: 0, w: 0, d: 0, l: 0, gf: 0, ga: 0, pts: 0, form: [] }]))
  for (const f of FIXTURES) {
    if (f.comp !== 'L' || f.div !== div || f.status !== 'done' || !rows.has(f.home)) continue
    for (const [c, gf, ga] of [[f.home, f.hg, f.ag], [f.away, f.ag, f.hg]]) {
      const r = rows.get(c)
      r.p += 1; r.gf += gf; r.ga += ga
      if (gf > ga) { r.w += 1; r.pts += 3; r.form.push('W') } else if (gf === ga) { r.d += 1; r.pts += 1; r.form.push('D') } else { r.l += 1; r.form.push('L') }
    }
  }
  return [...rows.values()].sort((a, b) => b.pts - a.pts || b.w - a.w || b.gf - b.ga - (a.gf - a.ga) || b.gf - a.gf).map((r, i) => ({ ...r, pos: i + 1, form: r.form.slice(-5) }))
}
const ROUNDS = { A: 38, B: 40, C: 31, D: 36 }
const NAME = (d) => `Liga Online ${d}`
const curRound = (div) => Math.min(...FIXTURES.filter((f) => f.div === div && f.status !== 'done').map((f) => f.round), ROUNDS[div])

export const seriesStatus = () => {
  const t = tableOf('D', ME.grp)
  const me = t.find((r) => r.id === ME.id)
  const next = mineList().find((f) => f.status !== 'done')
  const last = mineList().filter((f) => f.status === 'done').at(-1)
  const opp = (f) => byId.get(f.home === ME.id ? f.away : f.home)
  return {
    league: { div: 'D', name: NAME('D'), grp: ME.grp, size: 30, season: 7, start: START.toISOString().slice(0, 10) },
    day: { n: curRound('D'), of: 36, round: true },
    position: me.pos,
    standing: { p: me.p, w: me.w, d: me.d, l: me.l, gf: me.gf, ga: me.ga, pts: me.pts },
    form: me.form,
    next: next && { id: next.id, comp: next.comp, div: next.div, leg: next.leg, round: next.round, stage: next.stage, kickoff: next.kickoff, status: next.status, live: new Date(next.kickoff) <= new Date(), at_home: next.home === ME.id, opp: { ...club(opp(next)), position: 5 } },
    last: last && { id: last.id, hg: last.hg, ag: last.ag, at_home: last.home === ME.id, comp: last.comp, div: last.div, stage: last.stage, round: last.round, opp: club(opp(last)) },
  }
}

export const seriesRpc = {
  on_calendar: () => {
    const list = mineList()
    return {
      server_now: new Date().toISOString(), my_club: ME.id, series: true, start: START.toISOString().slice(0, 10), club: club(ME),
      clubs: [...new Set(list.map((f) => (f.home === ME.id ? f.away : f.home)))].map((x) => club(byId.get(x))),
      fixtures: list.map(({ id: i, comp, div, round, stage, leg, home, away, kickoff, status, hg, ag, pens }) => ({ id: i, comp, div, round, stage, leg, home, away, kickoff, status, hg, ag, pens })),
    }
  },
  on_standings: ({ p_div }) => {
    const d = p_div || 'D'
    const tables = d === 'D' ? [1, 2].map((g) => ({ phase: 1, grp: g, rows: tableOf('D', g) })) : [{ phase: 1, grp: 0, rows: tableOf(d, 0) }]
    return { my_club: ME.id, my_div: 'D', div: d, name: NAME(d), size: CLUBS.filter((c) => c.div === d).length, rounds: ROUNDS[d], current_round: curRound(d), tables, ties: [] }
  },
  on_round: ({ p_div, p_round }) => {
    const d = p_div || 'D'
    const r = p_round || curRound(d)
    const last = Math.max(...FIXTURES.filter((f) => f.div === d).map((f) => f.round))
    const live = (f) => f.status !== 'done' && new Date(f.kickoff) <= new Date()
    return {
      server_now: new Date().toISOString(), div: d, name: NAME(d), round: r, rounds: ROUNDS[d], last_round: last, my_club: ME.id,
      fixtures: FIXTURES.filter((f) => f.div === d && f.round === r).sort((a, b) => (a.grp || 0) - (b.grp || 0) || a.id - b.id).map((f) => ({
        id: f.id, kickoff: f.kickoff, status: live(f) ? 'live' : f.status, hg: f.hg, ag: f.ag, stage: f.stage, leg: f.leg, grp: f.grp,
        home: club(byId.get(f.home)), away: club(byId.get(f.away)), live: live(f) ? { minute: 34, score: [1, 0] } : null,
      })),
    }
  },
  on_cup: () => {
    const stages = ['f1', 'f2'].map((stage) => ({
      stage,
      ties: FIXTURES.filter((f) => f.comp === 'C' && f.stage === stage).map((f) => ({
        tie: f.tie, winner: f.status === 'done' ? cupWinner(f) : null, home: club(byId.get(f.home)), away: club(byId.get(f.away)),
        legs: [{ id: f.id, leg: null, home: f.home, hg: f.hg, ag: f.ag, pens: f.pens, status: f.status, kickoff: f.kickoff }], mine: f.home === ME.id || f.away === ME.id,
      })).sort((a, b) => b.mine - a.mine),
    }))
    return { my_club: ME.id, series: true, stages, rounds: [], history: [{ season: 6, champion: 'FC Edson', cup: 'FC Jeff', series: null }] }
  },
}
