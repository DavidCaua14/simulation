import { COMPETITIONS, COMP_ORDER, phaseIndex, phaseOf, roundTitle } from './seasonUtils'

// Funções puras: recebem os dados já carregados e devolvem o que a tela precisa.
// Nada aqui chama o banco, por isso trocar de aba é instantâneo.

// Quantas rodadas cada campeonato tem numa temporada (configuração: rules.calendar_rounds).
// Serve para intercalar os campeonatos de forma proporcional (mesma regra do banco, função sim_next_event).
const LEGACY_ROUNDS = { libertadores: 13, copa_brasil: 7, brasileirao: 38 }
export const expectedRounds = (id) => COMPETITIONS[id]?.rules?.calendar_rounds || LEGACY_ROUNDS[id] || 38
// compatibilidade: EXPECTED_MATCHES[id]
export const EXPECTED_MATCHES = new Proxy({}, { get: (_, id) => expectedRounds(id) })
const priorityOf = (id) => COMPETITIONS[id]?.rules?.calendar_priority ?? { libertadores: 1, copa_brasil: 2, brasileirao: 3 }[id] ?? 9

const progress = (id, played) => played / expectedRounds(id)
const byPriority = (a, b) => priorityOf(a) - priorityOf(b) || a.localeCompare(b)
export const involves = (f, club) => f.home_club === club || f.away_club === club

export function flattenFixtures(byComp = {}) {
  return Object.keys(byComp).flatMap((comp) => (byComp[comp] || []).map((f) => ({ ...f, comp })))
}

const newestFirst = (a, b) => (b.played_at || '').localeCompare(a.played_at || '') || b.id - a.id

// Histórico: todas as partidas que VOCÊ jogou (inclusive de clubes anteriores), da mais recente para a mais antiga.
export const playerHistory = (flat) => flat.filter((f) => f.player_match && f.status === 'played').sort(newestFirst)

// CALENDÁRIO ÚNICO da temporada (mesma regra do banco, função sim_next_event): em cada "dia" acontece
// a próxima rodada do campeonato mais atrasado. Se o seu clube joga nela -> "mine" (você simula, 1 energia);
// se não -> "free" (outro campeonato: o botão "Próximo" simula, sem energia).
export function projectCalendar(byComp, myClub, count = 14) {
  const pending = {}
  const done = {}
  const comps = COMP_ORDER.length ? COMP_ORDER : Object.keys(byComp)
  for (const comp of comps) {
    const all = buildRounds(byComp[comp] || [])
    done[comp] = all.filter((r) => r.done).length
    pending[comp] = all.filter((r) => !r.done)
  }
  const out = []
  while (out.length < count) {
    const ids = comps.filter((id) => pending[id].length)
    if (!ids.length) break
    ids.sort((a, b) => progress(a, done[a]) - progress(b, done[b]) || byPriority(a, b))
    const comp = ids[0]
    const round = pending[comp].shift()
    done[comp] += 1
    const mine = round.matches.find((f) => f.status === 'pending' && involves(f, myClub))
    out.push({
      kind: mine ? 'mine' : 'free',
      comp,
      stage: round.stage,
      round: round.round,
      label: round.label,
      fixture: mine ? { ...mine, comp } : null,
      matches: round.matches.length,
    })
  }
  return out
}

// Classificação calculada no app (mesmos critérios do banco: pontos, vitórias, saldo, gols pró).
export function standingsFrom(fixtures = [], group = null) {
  const rows = new Map()
  const row = (id) => {
    if (!rows.has(id)) rows.set(id, { club_id: id, played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0 })
    return rows.get(id)
  }
  for (const f of fixtures) {
    if (f.stage !== 'league' && f.stage !== 'group') continue
    if (group && f.group_label !== group) continue
    const h = row(f.home_club)
    const a = row(f.away_club)
    if (f.status !== 'played') continue
    h.played += 1
    a.played += 1
    h.gf += f.home_goals
    h.ga += f.away_goals
    a.gf += f.away_goals
    a.ga += f.home_goals
    if (f.home_goals > f.away_goals) (h.wins += 1), (a.losses += 1)
    else if (f.home_goals < f.away_goals) (a.wins += 1), (h.losses += 1)
    else (h.draws += 1), (a.draws += 1)
  }
  return [...rows.values()]
    .map((r) => ({ ...r, gd: r.gf - r.ga, points: r.wins * 3 + r.draws }))
    .sort((x, y) => y.points - x.points || y.wins - x.wins || y.gd - x.gd || y.gf - x.gf || x.club_id.localeCompare(y.club_id))
    .map((r, i) => ({ ...r, pos: i + 1 }))
}

export const groupOf = (fixtures = [], club) => fixtures.find((f) => f.stage === 'group' && involves(f, club))?.group_label ?? null

// Rodadas de um campeonato, em ordem: (fase, número). Cada rodada traz todos os jogos dela.
export function buildRounds(fixtures = []) {
  const map = new Map()
  for (const f of fixtures) {
    const key = `${f.stage}:${f.round_no}`
    if (!map.has(key)) map.set(key, { key, stage: f.stage, round: f.round_no, comp: f.competition_id, matches: [] })
    map.get(key).matches.push(f)
  }
  return [...map.values()]
    .sort((a, b) => phaseIndex(a.comp, a.stage) - phaseIndex(b.comp, b.stage) || a.round - b.round)
    .map((r) => ({
      ...r,
      label: roundTitle(r.stage, r.round, r.comp),
      matches: r.matches.sort((x, y) => (x.group_label || '').localeCompare(y.group_label || '') || x.id - y.id),
      done: r.matches.every((m) => m.status === 'played'),
    }))
}

// Rodada que deve abrir por padrão: a do seu último jogo; senão, a primeira ainda não terminada.
export function defaultRoundIndex(rounds, lastKey) {
  const i = lastKey ? rounds.findIndex((r) => r.key === lastKey) : -1
  if (i >= 0) return i
  const open = rounds.findIndex((r) => !r.done)
  return open >= 0 ? open : Math.max(0, rounds.length - 1)
}

// Últimos resultados de um clube, do mais antigo ao mais novo: ['W','D','L',...]
export function clubForm(flat, club, n = 5) {
  return flat
    .filter((f) => f.status === 'played' && involves(f, club))
    .sort(newestFirst)
    .slice(0, n)
    .reverse()
    .map((f) => {
      const mine = f.home_club === club ? f.home_goals : f.away_goals
      const opp = f.home_club === club ? f.away_goals : f.home_goals
      return mine > opp ? 'W' : mine === opp ? 'D' : 'L'
    })
}

// Resultado do ponto de vista do seu clube ('win' | 'draw' | 'loss' | null se o clube não jogou)
export function sideResult(f, club) {
  if (f.status !== 'played' || !involves(f, club)) return null
  const mine = f.home_club === club ? f.home_goals : f.away_goals
  const opp = f.home_club === club ? f.away_goals : f.home_goals
  return mine > opp ? 'win' : mine === opp ? 'draw' : 'loss'
}

// Próxima partida do SEU clube quando hoje não é dia de jogo dele: mesmo formato de hub.next_event (kind 'mine'),
// montado com o calendário projetado e os jogos já carregados. Só exibe o confronto; quem decide a data é o banco.
export function upcomingMatch(calendar, byComp, myClub) {
  const ev = calendar.find((e) => e.kind === 'mine' && e.fixture)
  if (!ev) return null
  const f = ev.fixture
  const comp = f.comp
  const opp = f.home_club === myClub ? f.away_club : f.home_club
  const fixtures = byComp[comp] || []
  const table = ['league', 'group'].includes(f.stage) ? standingsFrom(fixtures, f.stage === 'group' ? f.group_label : null) : []
  const flat = flattenFixtures(byComp)
  const recent = (club) => clubForm(flat, club).reverse() // mais recente primeiro, como o banco envia
  return {
    kind: 'mine',
    competition: comp,
    stage: f.stage,
    round: f.round_no,
    fixture_id: f.id,
    opponent: opp,
    opponent_position: table.find((r) => r.club_id === opp && r.played > 0)?.pos ?? null,
    my_position: table.find((r) => r.club_id === myClub && r.played > 0)?.pos ?? null,
    form: { mine: recent(myClub), opp: recent(opp) },
    match: {
      home: f.home_club,
      away: f.away_club,
      round: f.round_no,
      stage: f.stage,
      leg: f.leg,
      group: f.group_label,
      competition: comp,
      venue: f.home_club === myClub ? 'home' : 'away',
      neutral: phaseOf(comp, f.stage)?.neutral ?? f.stage === 'final',
    },
    projected: true,
  }
}
