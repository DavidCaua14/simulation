import { useEffect, useMemo, useState } from 'react'
import { ClipboardList, Flag, Play, Shirt } from 'lucide-react'
import GameIcon from '../../../components/ui/GameIcon'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { isSessionError } from '../../../lib/sessionRecovery'
import useCatalog from '../hooks/useCatalog'
import { fetchOpponentReport, fetchSquad } from '../services/managerApi'
import { lineupStrength } from '../utils/managerUtils'
import { COMP_NAME, ordinal } from '../utils/seasonUtils'
import { dateLabel } from '../services/careerWorldApi'

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }
const ROWS = [
  ['overall', 'Geral'],
  ['att', 'Ataque'],
  ['mid', 'Meio-campo'],
  ['def', 'Defesa'],
  ['gk', 'Goleiro'],
]

// Escalação provável do rival (mesma ideia do auxiliar do banco): cada vaga recebe quem rende mais nela.
function probableXI(formation, players) {
  if (!formation) return {}
  const weight = (p, pos) => (p.ratings?.[pos] ?? 0) * (p.available === false ? 0.001 : 1) * (p.condition < 60 ? 0.9 : 1)
  const pool = [...players]
  const slots = {}
  for (const s of [...formation.slots].sort((a, b) => SCARCITY[a.pos] - SCARCITY[b.pos])) {
    let best = -1
    for (let i = 0; i < pool.length; i++) if (best < 0 || weight(pool[i], s.pos) > weight(pool[best], s.pos)) best = i
    if (best >= 0) slots[s.slot] = pool.splice(best, 1)[0].id
  }
  return slots
}

function LineupList({ formation, slots, byId, side, label }) {
  if (!formation) return <div className="vs-list st-sk" />
  const order = [...formation.slots].sort((a, b) => (SCARCITY[a.pos] - SCARCITY[b.pos]) || b.y - a.y)
  return (
    <section className={`vs-list is-${side}`}>
      <header>
        <b>{label}</b>
        <em>{formation.name || formation.id}</em>
      </header>
      <ol>
        {order.map((s) => {
          const p = byId[slots?.[s.slot]]
          return (
            <li key={s.slot} className={p?.available === false ? 'is-out' : ''}>
              <i>{s.pos}</i>
              <span>{p ? p.short_name || p.name : '—'}</span>
            </li>
          )
        })}
      </ol>
    </section>
  )
}

// PRÉ-JOGO no formato do CM17: os dois times frente a frente, comparação de força por setor,
// exercícios pré-jogo e os botões Escalação / Instruções / Funções / Pontapé inicial.
export default function PreMatchVS({ next, myClub, myPos, today, ready, waitingText, canPlay, blockedText, starting, engineVersion = 1, drills = null, onLineup, onTactics, onRoles, onStart }) {
  const { catalog } = useCatalog()
  const m = next.match
  const oppId = m.home === myClub ? m.away : m.home
  const [mine, setMine] = useState(null)
  const [opp, setOpp] = useState(null)
  const [report, setReport] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    const fail = (e) => alive && !isSessionError(e) && setError(e.message || 'Não foi possível carregar os elencos.')
    fetchSquad().then((s) => alive && setMine(s)).catch(fail)
    fetchSquad(oppId).then((s) => alive && setOpp(s)).catch(fail)
    if (engineVersion >= 2) fetchOpponentReport(next.fixture_id).then((r) => alive && setReport(r)).catch(() => alive && setReport({ error: true }))
    return () => {
      alive = false
    }
  }, [oppId, next.fixture_id, engineVersion])

  const myById = useMemo(() => Object.fromEntries((mine?.players || []).map((p) => [p.id, p])), [mine])
  const oppById = useMemo(() => Object.fromEntries((opp?.players || []).map((p) => [p.id, p])), [opp])
  const myFormation = catalog?.byId[mine?.lineup?.formation]
  const oppFormation = catalog?.byId[report && !report.error ? report.formation : null] || catalog?.byId['4-3-3'] || catalog?.formations?.[0]
  const oppSlots = useMemo(() => probableXI(oppFormation, opp?.players || []), [oppFormation, opp])
  const my = useMemo(() => (myFormation ? lineupStrength(myFormation, mine?.lineup?.slots, myById) : null), [myFormation, mine, myById])
  const op = useMemo(() => (oppFormation ? lineupStrength(oppFormation, oppSlots, oppById) : null), [oppFormation, oppSlots, oppById])
  const errors = mine?.lineup?.issues?.filter((i) => i.level === 'error').length || 0
  const home = m.home === myClub
  const sideOf = (club) => (club === myClub ? { pos: myPos, label: 'Seu time' } : { pos: next.opponent_position, label: 'Adversário' })
  const disabled = starting || !ready || !canPlay || errors > 0

  return (
    <div className="vs">
      <header className="vs-head">
        {[m.home, m.away].map((club, i) => (
          <div key={club} className={`vs-club ${club === myClub ? 'is-mine' : ''} ${i ? 'is-away' : ''}`}>
            <ClubCrest clubId={club} size={52} />
            <span>
              <small>{sideOf(club).pos ? `${ordinal(sideOf(club).pos)} na tabela` : sideOf(club).label}</small>
              <b>{getClubById(club)?.name}</b>
            </span>
          </div>
        ))}
        <div className="vs-mid">
          <small>{today ? dateLabel(today) : ''}</small>
          <b>VS</b>
        </div>
      </header>
      <div className="vs-strip">
        <span>{getClubById(m.home)?.stadium || (home ? 'Em casa' : 'Fora de casa')}</span>
        <b>{COMP_NAME[next.competition] || next.competition}</b>
        <span>{m.neutral ? 'Campo neutro' : home ? 'Mandante' : 'Visitante'}</span>
      </div>

      {error && <p className="sn-muted sn-center">{error}</p>}

      <div className="vs-body">
        <LineupList formation={home ? myFormation : oppFormation} slots={home ? mine?.lineup?.slots : oppSlots} byId={home ? myById : oppById} side="home" label="Início" />
        <section className="vs-compare" aria-label="Força por setor">
          {ROWS.map(([k, label]) => {
            const a = home ? my?.[k] : op?.[k]
            const b = home ? op?.[k] : my?.[k]
            return (
              <div key={k}>
                <small>{label}</small>
                <span>
                  <b className={a >= b ? 'is-up' : 'is-down'}>{a ?? '–'}</b>
                  <b className={b >= a ? 'is-up' : 'is-down'}>{b ?? '–'}</b>
                </span>
              </div>
            )
          })}
        </section>
        <LineupList formation={home ? oppFormation : myFormation} slots={home ? oppSlots : mine?.lineup?.slots} byId={home ? oppById : myById} side="away" label="Vis." />
      </div>

      {drills}

      <div className="vs-actions">
        <button type="button" className="gx-btn-ghost" onClick={onLineup} disabled={starting}>
          <Shirt size={16} /> Escalação
        </button>
        <button type="button" className="gx-btn-ghost" onClick={onTactics} disabled={starting}>
          <ClipboardList size={16} /> Instruções
        </button>
        <button type="button" className="gx-btn-ghost" onClick={onRoles} disabled={starting}>
          <Flag size={16} /> Funções
        </button>
        <button type="button" className="gx-btn vs-kick" onClick={onStart} disabled={disabled}>
          {starting ? (
            <>
              <span className="nm-spin" /> Entrando em campo…
            </>
          ) : !ready ? (
            <>
              <span className="nm-spin" /> {waitingText || 'Aguarde…'}
            </>
          ) : !canPlay ? (
            <>
              <GameIcon name="lock" size={16} /> {blockedText}
            </>
          ) : errors ? (
            'Corrija a escalação'
          ) : (
            <>
              <Play size={17} fill="currentColor" /> Pontapé inicial
              <span className="nm-cost" title="Custa 1 de energia">
                <GameIcon name="energy" size={13} />1
              </span>
            </>
          )}
        </button>
      </div>
    </div>
  )
}
