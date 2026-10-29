import GameIcon from '../../../components/ui/GameIcon'
import { useEffect, useMemo, useState } from 'react'
import { Ambulance, Ban, Play, Shirt, ShieldAlert } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { isSessionError } from '../../../lib/sessionRecovery'
import Sheet from '../ui/Sheet'
import Pitch from './Pitch'
import FormDots from './FormDots'
import { OpponentTactics } from './OpponentScout'
import useCatalog from '../hooks/useCatalog'
import { fetchOpponentReport, fetchSquad } from '../services/managerApi'
import { lineupStrength } from '../utils/managerUtils'
import { COMP_NAME, describeMatch, ordinal, venueLabel } from '../utils/seasonUtils'

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }
const SECTORS = [
  ['gk', 'Goleiro'],
  ['def', 'Defesa'],
  ['mid', 'Meio-campo'],
  ['att', 'Ataque'],
]

// Escalação provável do rival: mesma ideia do auxiliar do banco (mgr_auto_lineup) — cada vaga recebe quem
// rende mais nela, com peso para condição física; indisponíveis só entram se não houver mais ninguém.
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

function Team({ clubId, mine, pos, form }) {
  const club = getClubById(clubId)
  return (
    <div className={`pm-team ${mine ? 'is-mine' : ''}`}>
      <ClubCrest clubId={clubId} size={48} />
      <b>{club?.name}</b>
      <small>{mine ? 'Seu time' : pos ? `${ordinal(pos)} na tabela` : 'Adversário'}</small>
      <FormDots form={[...(form || [])].reverse()} />
    </div>
  )
}

// PRÉ-JOGO: confronto, escalações dos dois times, análise do adversário e o botão que inicia a simulação.
// Abrir esta tela não gasta energia; a partida só começa em "Iniciar partida".
export default function PreMatch({ next, myClub, myPos, lineupErrors = 0, canPlay, blockedText, starting, engineVersion = 1, onStart, onLineup, onClose }) {
  const { catalog, error: catErr } = useCatalog()
  const m = next.match
  const oppId = m.home === myClub ? m.away : m.home
  const [tab, setTab] = useState('lineups')
  const [side, setSide] = useState('mine')
  const [mine, setMine] = useState(null)
  const [opp, setOpp] = useState(null)
  const [report, setReport] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    const fail = (e) => alive && !isSessionError(e) && setError(e.message || 'Não foi possível carregar os elencos.')
    fetchSquad().then((s) => alive && setMine(s)).catch(fail)
    fetchSquad(oppId).then((s) => alive && setOpp(s)).catch(fail)
    if (engineVersion >= 2) {
      fetchOpponentReport(next.fixture_id)
        .then((r) => alive && setReport(r))
        .catch((e) => alive && !isSessionError(e) && setReport({ error: true }))
    }
    return () => {
      alive = false
    }
  }, [oppId, next.fixture_id, engineVersion])

  const myById = useMemo(() => Object.fromEntries((mine?.players || []).map((p) => [p.id, p])), [mine])
  const oppById = useMemo(() => Object.fromEntries((opp?.players || []).map((p) => [p.id, p])), [opp])
  const myFormation = catalog?.byId[mine?.lineup?.formation]
  const oppFormationId = report && !report.error ? report.formation : null
  const oppFormation = catalog?.byId[oppFormationId] || catalog?.byId['4-3-3'] || catalog?.formations?.[0]
  const oppSlots = useMemo(() => probableXI(oppFormation, opp?.players || []), [oppFormation, opp])
  const myStrength = useMemo(() => (myFormation ? lineupStrength(myFormation, mine?.lineup?.slots, myById) : null), [myFormation, mine, myById])
  const oppStrength = useMemo(() => (oppFormation ? lineupStrength(oppFormation, oppSlots, oppById) : null), [oppFormation, oppSlots, oppById])
  const myOut = (mine?.players || []).filter((p) => p.available === false)
  const oppOut = (opp?.players || []).filter((p) => p.available === false)
  const venue = venueLabel(m)
  const myColors = getClubById(myClub)?.colors
  const oppColors = getClubById(oppId)?.colors

  const footer = (
    <>
      <button type="button" className="gx-btn-ghost" disabled={starting} onClick={onLineup}>
        <Shirt size={16} /> Escalação
      </button>
      <button type="button" className={`gx-btn pm-start ${canPlay && !lineupErrors ? 'is-ready' : ''}`} disabled={starting || !canPlay || lineupErrors > 0} onClick={onStart}>
        {starting ? (
          <>
            <span className="nm-spin" /> Entrando em campo…
          </>
        ) : !canPlay ? (
          <>
            <GameIcon name="lock" size={16} /> {blockedText}
          </>
        ) : lineupErrors ? (
          <>
            <ShieldAlert size={16} /> Corrija a escalação
          </>
        ) : (
          <>
            <Play size={18} fill="currentColor" /> Iniciar partida
            <span className="nm-cost" title="Custa 1 de energia">
              <GameIcon name="energy" size={13} />1
            </span>
          </>
        )}
      </button>
    </>
  )

  return (
    <Sheet kicker={COMP_NAME[next.competition]} title={describeMatch(m)} onClose={starting ? undefined : onClose} footer={footer} tall className="pm">
      <div className="pm-versus">
        <Team clubId={m.home} mine={m.home === myClub} pos={m.home === myClub ? myPos : next.opponent_position} form={m.home === myClub ? next.form?.mine : next.form?.opp} />
        <div className="pm-mid">
          <span>VS</span>
          {venue && <small>{venue}</small>}
        </div>
        <Team clubId={m.away} mine={m.away === myClub} pos={m.away === myClub ? myPos : next.opponent_position} form={m.away === myClub ? next.form?.mine : next.form?.opp} />
      </div>

      <div className="sn-seg" role="tablist">
        {[
          ['lineups', 'Escalações'],
          ['scout', 'Análise do adversário'],
        ].map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
            {label}
          </button>
        ))}
      </div>

      {(error || catErr) && <p className="sn-muted sn-center">{error || catErr}</p>}

      {tab === 'lineups' && (
        <section className="pm-sec">
          <div className="pm-toggle">
            <button type="button" className={side === 'mine' ? 'is-on' : ''} onClick={() => setSide('mine')}>
              <ClubCrest clubId={myClub} size={18} /> {getClubById(myClub)?.name}
            </button>
            <button type="button" className={side === 'opp' ? 'is-on' : ''} onClick={() => setSide('opp')}>
              <ClubCrest clubId={oppId} size={18} /> {getClubById(oppId)?.name}
            </button>
          </div>
          {side === 'mine' ? (
            !mine || !catalog ? (
              <div className="st-sk hero" />
            ) : (
              <>
                <p className="pm-formation">
                  <b>{mine.lineup?.formation}</b> · sua escalação salva
                </p>
                <Pitch formation={myFormation} slots={mine.lineup?.slots} playersById={myById} colors={myColors} compact />
                <OutList players={myOut} title="Desfalques do seu time" />
              </>
            )
          ) : !opp || !catalog || (engineVersion >= 2 && !report) ? (
            <div className="st-sk hero" />
          ) : (
            <>
              <p className="pm-formation">
                <b>{oppFormation?.id}</b> · escalação provável
              </p>
              <Pitch formation={oppFormation} slots={oppSlots} playersById={oppById} colors={oppColors} compact />
              <p className="sn-hint">O rival pode mudar o time e o plano até o apito inicial.</p>
              <OutList players={oppOut} title="Desfalques do adversário" />
            </>
          )}
        </section>
      )}

      {tab === 'scout' && (
        <section className="pm-sec">
          {myStrength && oppStrength && (
            <div className="pm-compare">
              <h4>Força por setor</h4>
              {SECTORS.map(([k, label]) => (
                <div key={k} className="pm-bar">
                  <b>{myStrength[k]}</b>
                  <span>
                    <i className="is-mine" style={{ width: `${(100 * myStrength[k]) / Math.max(1, myStrength[k] + oppStrength[k])}%` }} />
                    <i style={{ width: `${(100 * oppStrength[k]) / Math.max(1, myStrength[k] + oppStrength[k])}%` }} />
                  </span>
                  <b>{oppStrength[k]}</b>
                  <small>{label}</small>
                </div>
              ))}
            </div>
          )}
          {engineVersion < 2 ? (
            <p className="sn-muted">A análise tática do rival fica disponível com o novo motor de partidas.</p>
          ) : !report ? (
            <p role="status" className="sn-muted">Analisando o rival...</p>
          ) : report.error ? (
            <p role="alert" className="sn-muted">Não foi possível analisar o rival agora.</p>
          ) : (
            <div className="opponent-scout pm-scout">
              <OpponentTactics {...report} />
            </div>
          )}
        </section>
      )}
    </Sheet>
  )
}

function OutList({ players, title }) {
  if (!players.length) return null
  return (
    <div className="pm-out">
      <h4>{title}</h4>
      <ul>
        {players.map((p) => (
          <li key={p.id}>
            {p.injured_days > 0 ? <Ambulance size={13} /> : <Ban size={13} />}
            <b>{p.short_name || p.name}</b>
            <small>
              {p.position} · {p.injured_days > 0 ? `lesionado (${p.injured_days} dia${p.injured_days > 1 ? 's' : ''})` : 'suspenso'}
            </small>
          </li>
        ))}
      </ul>
    </div>
  )
}
