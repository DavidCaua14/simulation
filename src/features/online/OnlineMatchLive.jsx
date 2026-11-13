import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Ambulance, ArrowLeft, ClipboardList, MapPin, Megaphone, Radio, Repeat2, Shield, Swords, Scale, Trophy, Tv, Users, Wifi, WifiOff, Zap } from 'lucide-react'
import { isSessionError } from '../../lib/sessionRecovery'
import MatchTactical2D from '../match2d/MatchTactical2D'
import MatchLineupEditor, { draftFromMatch } from '../seasons/components/MatchLineupEditor'
import useCatalog from '../seasons/hooks/useCatalog'
import { MAJOR_EVENTS, condTone, eventText, isGoal, posFit } from '../seasons/utils/managerUtils'
import useMatchAudio from '../audio/useMatchAudio'
import LineupsSheet, { LineupsView } from './components/LineupsSheet'
import OnlineCrest from './components/OnlineCrest'
import { OvrBadge } from './components/PlayerFut'
import { actOnlineMatch, fetchOnlineScout, fetchOnlineSquad, pollOnlineMatch, sendOnlineHalftimeTalk } from './services/onlineApi'
import { kickoffState } from './kickoffState'
import { SCREEN_LAG_MS, asSeasonPlayer, clockPhase, clubColors, matchClock } from './onlineUtils'
import '../seasons/seasons.css'
import '../seasons/manager.css'
import '../seasons/matchflow/matchflow.css'

const POLL_MS = 20000
const SHOT_KINDS = new Set(['goal', 'pen_goal', 'save', 'shot_off', 'pen_miss'])
// Postura do time: muda na hora, sem abrir o painel de instruções.
const STYLES = [
  ['defensive', 'Defensivo', Shield],
  ['neutral', 'Equilibrado', Scale],
  ['attacking', 'Ofensivo', Swords],
  ['counter', 'Contra-ataque', Zap],
]
// Preleção do intervalo: o efeito depende do placar e de quem é o favorito (pode ajudar ou atrapalhar).
const HT_TALKS = [
  ['praise', 'Elogiar', 'Estou satisfeito. Continuem assim.'],
  ['focus', 'Pedir foco', 'Não relaxem, o jogo não acabou.'],
  ['demand', 'Cobrar mais', 'Espero muito mais de vocês.'],
  ['encourage', 'Incentivar', 'Vocês conseguem. Acreditem!'],
  ['calm', 'Tirar a pressão', 'Sem pressão. Joguem soltos.'],
  ['angry', 'Dar bronca', 'Isso não é aceitável!'],
]
const HT_REACT = { fired: 'O time voltou inflamado', good: 'O time reagiu bem', flat: 'Pouco efeito', upset: 'O time não gostou' }
const LINES = [['DEF', 'Defesa'], ['MID', 'Meio'], ['ATT', 'Ataque']]
const TABS = [
  ['feed', 'Lances'],
  ['stats', 'Estatísticas'],
  ['ratings', 'Notas'],
  ['lineups', 'Times'],
]

// PARTIDA AO VIVO DO MODO ONLINE. O relógio é real (12 minutos, no horário marcado) e não para para ninguém.
// A tela consulta o servidor a cada 20 s e mostra o jogo ~3 minutos atrás dele, para nunca ficar sem lances.
// As mudanças do técnico valem no minuto em que o servidor está ("vale a partir de X'").
export default function OnlineMatchLive({ fixtureId = null, onClose, notify }) {
  const { catalog } = useCatalog()
  const [data, setData] = useState(null)
  const [events, setEvents] = useState([])
  const [error, setError] = useState('')
  const [offset, setOffset] = useState(0)
  const [now, setNow] = useState(() => Date.now())
  const [tab, setTab] = useState('feed')
  const [panel, setPanel] = useState(false)
  const [lineups, setLineups] = useState(false)
  const [busy, setBusy] = useState(false)
  const [applied, setApplied] = useState(null) // {minute, until} aviso "vale a partir de X'"
  const [squadById, setSquadById] = useState(null)
  const [scout, setScout] = useState(null) // vestiário: comparação dos times (só no jogo do próprio técnico)
  const [revealed, setRevealed] = useState(() => new Set())
  const [online, setOnline] = useState(true)
  const [broadcast, setBroadcast] = useState(() => {
    try {
      return window.localStorage.getItem('sim.broadcast') !== 'off'
    } catch {
      return true
    }
  })
  // no vestiário ou na partida, o aviso de "seu jogo vai começar" não aparece
  useEffect(() => {
    kickoffState.inMatchRoom = true
    return () => {
      kickoffState.inMatchRoom = false
    }
  }, [])
  const lastSeq = useRef(0)
  const idRef = useRef(fixtureId)

  const merge = useCallback((r) => {
    if (!r) return
    if (r.server_now) setOffset(new Date(r.server_now).getTime() - Date.now())
    idRef.current = r.fixture_id
    setEvents((prev) => {
      const seen = new Set(prev.map((e) => e.seq))
      const add = (r.events || []).filter((e) => !seen.has(e.seq))
      if (!add.length) return prev
      lastSeq.current = Math.max(lastSeq.current, ...add.map((e) => e.seq))
      return [...prev, ...add].sort((a, b) => a.seq - b.seq)
    })
    setData(r)
  }, [])

  // ---- consulta periódica (40 s); nada mais vai ao banco ----
  const poll = useCallback(async () => {
    try {
      merge(await pollOnlineMatch(idRef.current, lastSeq.current))
      setOnline(true)
      setError('')
    } catch (e) {
      if (isSessionError(e)) return
      setOnline(false)
      setError(e.message)
    }
  }, [merge])
  const status = data?.status
  useEffect(() => {
    poll()
    if (status === 'finished') return undefined
    const id = setInterval(poll, POLL_MS)
    return () => clearInterval(id)
  }, [poll, status])
  // antes do pontapé: consulta de novo exatamente no horário
  const kick = data ? new Date(data.kickoff).getTime() : null
  useEffect(() => {
    if (status !== 'sched' || !kick) return undefined
    const wait = kick - (Date.now() + offset) + 1500
    if (wait > POLL_MS) return undefined
    const t = setTimeout(poll, Math.max(500, wait))
    return () => clearTimeout(t)
  }, [status, kick, offset, poll])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 250)
    return () => clearInterval(id)
  }, [])

  const mySide = data?.my_side
  useEffect(() => {
    if (status !== 'sched' || !mySide || scout) return
    fetchOnlineScout(false).then(setScout).catch(() => {})
  }, [status, mySide, scout])
  const halftimeTalk = async (talk) => {
    if (busy) return
    setBusy(true)
    try {
      const r = await sendOnlineHalftimeTalk(data.fixture_id, talk)
      merge(r)
      const mine = r.ht_talk?.[r.my_side]
      notify?.(HT_REACT[mine?.react] || 'Preleção feita', mine?.react === 'upset' ? 'alert' : 'success')
    } catch (e) {
      if (!isSessionError(e)) notify?.(e.message, 'alert')
    } finally {
      setBusy(false)
    }
  }

  const serverNow = now + offset
  const et = Boolean(data?.et)
  const finished = status === 'finished'
  const endMin = et ? 120 : 90
  const raw = kick ? matchClock(kick, serverNow - SCREEN_LAG_MS, et) : -1
  // o relógio da tela nunca passa do servidor (a não ser que o jogo já tenha acabado)
  const clock = finished ? Math.max(0, raw) : Math.max(-1, Math.min(raw, data?.minute ?? 0))
  const shownMinute = Math.floor(Math.max(0, clock))
  const ended = finished && raw >= endMin
  const phase = kick ? clockPhase(kick, serverNow - SCREEN_LAG_MS, et) : 'pre'

  const onReveal = useCallback((seqs) => {
    setRevealed((prev) => {
      const next = new Set(prev)
      for (const s of seqs) next.add(s)
      return next
    })
  }, [])
  const visible = useMemo(() => events.filter((e) => ended || e.minute <= shownMinute || revealed.has(e.seq)), [events, shownMinute, revealed, ended])
  const upcoming = useMemo(() => events.filter((e) => e.minute <= shownMinute + 1), [events, shownMinute])

  const live = useMemo(() => {
    const sc = { h: 0, a: 0 }
    const pens = { h: 0, a: 0 }
    const shots = { h: 0, a: 0 }
    const sot = { h: 0, a: 0 }
    const yel = { h: 0, a: 0 }
    const red = { h: 0, a: 0 }
    let so = false
    for (const e of visible) {
      if (!e.side) continue
      if (isGoal(e)) sc[e.side] += 1
      if (SHOT_KINDS.has(e.kind)) shots[e.side] += 1
      if (e.kind === 'goal' || e.kind === 'pen_goal' || e.kind === 'save' || (e.kind === 'pen_miss' && e.detail === 'defendido')) sot[e.side] += 1
      if (e.kind === 'yellow') yel[e.side] += 1
      if (e.kind === 'red' || e.kind === 'second_yellow') red[e.side] += 1
      if (e.kind === 'so_goal') (pens[e.side] += 1), (so = true)
      if (e.kind === 'so_miss') so = true
    }
    return { sc, pens, shots, sot, yel, red, so }
  }, [visible])

  const side = data?.my_side || null
  useMatchAudio({ visible, userSide: side || 'h', score: live.sc, minute: shownMinute, active: Boolean(data) && status !== 'sched' })

  // notas por posição do elenco para o editor do time
  useEffect(() => {
    if (!panel || squadById) return
    fetchOnlineSquad()
      .then((sq) => setSquadById(Object.fromEntries(sq.players.map((p) => [p.id, asSeasonPlayer(p, posFit)]))))
      .catch(() => setSquadById({}))
  }, [panel, squadById])

  const apply = async (changes) => {
    if (busy) return
    setBusy(true)
    try {
      const r = await actOnlineMatch(data.fixture_id, changes)
      merge(r)
      setApplied({ minute: r.applied_at, at: now })
      notify?.(`Ordem dada aos ${r.applied_at}'`, 'success')
    } catch (e) {
      if (!isSessionError(e)) notify?.(e.message, 'alert')
    } finally {
      setBusy(false)
    }
  }

  if (!data) {
    return (
      <div className="onm onm-loading" role="dialog" aria-modal="true" aria-label="Partida ao vivo">
        <button type="button" className="on-back" onClick={onClose} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <div className="onm-spinner" aria-hidden="true" />
        <p>{error || 'Entrando no estádio…'}</p>
      </div>
    )
  }

  const home = { ...data.home, colors: clubColors(data.home) }
  const away = { ...data.away, colors: clubColors(data.away) }
  const clubs = { home, away, crest: (sd) => <OnlineCrest club={sd === 'h' ? data.home : data.away} size={18} /> }
  const players = data.players || []
  const mine = side ? (side === 'h' ? data.home : data.away) : null
  const opp = side ? (side === 'h' ? data.away : data.home) : null
  const oppPresent = side ? Boolean(data.present?.[side === 'h' ? 'a' : 'h']) : false
  const myFormation = side ? data.formation?.[side === 'h' ? 0 : 1] : null
  const finalH = data.summary?.home_goals ?? live.sc.h
  const finalA = data.summary?.away_goals ?? live.sc.a
  const myGoals = side === 'h' ? finalH : finalA
  const oppGoals = side === 'h' ? finalA : finalH
  const myPrep = side ? data.prep?.[side === 'h' ? 0 : 1] : null
  const myTactics = side ? data.tactics?.[side] || {} : {}
  const myStyle = myTactics.style || (Number(myTactics.mentality || 0) < 0 ? 'defensive' : Number(myTactics.mentality || 0) > 0 ? 'attacking' : 'neutral')
  const injuredOff = side ? players.filter((p) => p.side === side && p.status === 'injured_off' && p.slot) : []
  const fixes = (data.fixes || []).map((f) => ({ ...f, inName: players.find((p) => p.id === f.in)?.name }))
  const clockLabel = phase === 'pre' || clock < 0 ? '0\'' : ended ? 'FIM' : phase === 'ht' ? 'INT' : phase === 'et_wait' ? 'PRO' : `${Math.min(shownMinute, endMin)}'`
  const feed = [...visible].reverse()
  const name = (sd) => (sd === 'h' ? data.home : data.away)?.name

  // ---- antes do pontapé ----
  if (status === 'sched' || clock < 0) {
    const left = Math.max(0, Math.round((kick - serverNow) / 1000))
    const mm = Math.floor(left / 60)
    const ss = String(left % 60).padStart(2, '0')
    const sc = scout && scout.fixture === data.fixture_id ? scout : null
    const meHome = side === 'h'
    const info = (sd) => (!sc || !side ? null : (sd === 'h') === meHome ? sc.me : sc.opp)
    const teamCol = (sd, club) => (
      <div className={`onm-vs-team ${side === sd ? 'is-mine' : ''}`}>
        <OnlineCrest club={club} size={80} />
        <b>{club.name}</b>
        <small>{info(sd) ? `${info(sd).position}º · ${info(sd).formation || '4-3-3'}` : sd === 'h' ? 'Mandante' : 'Visitante'}</small>
      </div>
    )
    return (
      <div className="onm onm-pre" role="dialog" aria-modal="true" aria-label="Vestiário">
        <header className="onm-pre-top">
          <button type="button" className="on-back" onClick={onClose} aria-label="Voltar"><ArrowLeft size={20} /></button>
          <span className="on-match-comp">{data.comp === 'C' ? 'Copa Online' : `Liga · Rodada ${data.round}`}</span>
        </header>
        <div className="onm-vs">
          {teamCol('h', data.home)}
          <span className="onm-vs-x">VS</span>
          {teamCol('a', data.away)}
        </div>
        {lineups && <LineupsSheet fixtureId={data.fixture_id} onClose={() => setLineups(false)} />}
        <p className="onm-pre-hint"><MapPin size={14} /> {data.home.colors?.stadium || `Arena ${data.home.short}`} · {new Date(data.kickoff).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</p>
        <div className="onm-count">
          {left > 0 ? (
            <>
              <small>Pontapé inicial em</small>
              <b>{left >= 3600 ? `${Math.floor(mm / 60)} h ${String(mm % 60).padStart(2, '0')}` : `${mm}:${ss}`}</b>
            </>
          ) : (
            <div className="onm-starting" role="status">
              <i className="onm-starting-ball" aria-hidden="true" />
              <b>A partida vai começar</b>
              <span className="onm-starting-bar" aria-hidden="true"><i /></span>
            </div>
          )}
        </div>
        <button type="button" className="gx-btn-ghost onm-pre-lus" onClick={() => setLineups(true)}><Users size={16} /> Ver escalações</button>
        {sc && (
          <>
            <div className="onm-pre-card">
              <h3 className="on-h">Confronto</h3>
              <div className="on-scout-bars">
                {LINES.map(([k, label]) => {
                  const mine = Number(sc.sectors?.me?.[k] ?? 0)
                  const theirs = Number(sc.sectors?.opp?.[k] ?? 0)
                  const h = meHome ? mine : theirs
                  const a = meHome ? theirs : mine
                  return (
                    <div key={k}>
                      <b>{Math.round(h)}</b>
                      <span><small>{label}</small><i className="is-neutral"><em style={{ width: `${h + a ? (h / (h + a)) * 100 : 50}%` }} /></i></span>
                      <b>{Math.round(a)}</b>
                    </div>
                  )
                })}
              </div>
            </div>
            <div className="onm-pre-card">
              <h3 className="on-h">Destaques</h3>
              <div className="onm-pre-stars">
                {[meHome ? sc.me : sc.opp, meHome ? sc.opp : sc.me].map((t, col) => (
                  <ul key={col} className={col ? 'is-away' : ''}>
                    {(t.stars || []).map((p) => <li key={p.id}><OvrBadge p={p} small /><span>{p.name}</span></li>)}
                  </ul>
                ))}
              </div>
            </div>
            {sc.prep && (
              <div className={`onm-pre-prep ${sc.prep.score >= 100 ? 'is-full' : ''}`}>
                <b>{sc.prep.score}%</b>
                <span><small>Preparação do time</small><strong>+{String(sc.prep.bonus).replace('.', ',')}% em campo</strong></span>
                {sc.prep.score < 100 && left > 60 && <button type="button" className="gx-btn-ghost" onClick={onClose}>Preparar</button>}
              </div>
            )}
          </>
        )}
      </div>
    )
  }

  return (
    <div className={`onm ml ${broadcast ? 'has-broadcast' : ''}`} role="dialog" aria-modal="true" aria-label="Partida ao vivo">
      {broadcast && catalog && (
        <div className="ml-stage">
          <MatchTactical2D
            data={{ ...data, home: data.home.id, away: data.away.id }}
            clubs={clubs}
            catalog={catalog}
            clock={Math.max(0, clock)}
            minute={shownMinute}
            events={upcoming}
            onHold={() => {}}
            onReveal={onReveal}
            paused={phase === 'ht' || ended}
            speed={1}
            score={live.sc}
            finished={ended}
            clockLabel={clockLabel}
            userSide={side || 'h'}
          />
        </div>
      )}
      <header className="ml-top onm-top" style={{ '--hc': home.colors[0], '--ac': away.colors[0] }}>
        <div className="ml-comp">
          <button type="button" className="onm-x" onClick={onClose} aria-label="Sair da partida"><ArrowLeft size={16} /></button>
          <span>{data.comp === 'C' ? 'Copa Online' : 'Liga Online'}</span>
          <em>{data.comp === 'C' ? data.stage : `Rodada ${data.round}`}</em>
          <span className={`pm-live ${ended ? 'is-done' : ''}`}>{ended ? 'Encerrado' : <><Radio size={11} /> Ao vivo</>}</span>
        </div>
        <div className="ml-board">
          <div className={`ml-team ${side === 'h' ? 'is-mine' : ''}`}>
            <OnlineCrest club={data.home} size={44} />
            <b>{data.home.short}</b>
          </div>
          <div className="ml-score">
            <span className="ml-goals">
              <b key={`h${live.sc.h}`}>{live.sc.h}</b>
              <i>:</i>
              <b key={`a${live.sc.a}`}>{live.sc.a}</b>
            </span>
            <span className="ml-clock">{clockLabel}</span>
            {live.so && <small className="ml-pens">Pênaltis {live.pens.h} – {live.pens.a}</small>}
          </div>
          <div className={`ml-team ${side === 'a' ? 'is-mine' : ''}`}>
            <OnlineCrest club={data.away} size={44} />
            <b>{data.away.short}</b>
          </div>
        </div>
        <div className="ml-progress" aria-hidden="true">
          <i style={{ width: `${(Math.min(Math.max(clock, 0), endMin) / endMin) * 100}%` }} />
        </div>
      </header>

      {side && !ended && (
        <div className="onm-presence">
          <span className="is-me"><Wifi size={13} /> No comando{data.ht_talk?.[side] ? ` · ${HT_REACT[data.ht_talk[side].react]}` : myPrep ? ` · preparo ${myPrep.score}% (+${String(myPrep.bonus).replace('.', ',')}%)` : ''}</span>
          <span className={oppPresent ? 'is-on' : ''}>
            {opp.bot ? <><Users size={13} /> {opp.short} · auxiliar</> : oppPresent ? <><Wifi size={13} /> {opp.short} · técnico no banco</> : <><WifiOff size={13} /> {opp.short} · auxiliar</>}
          </span>
        </div>
      )}
      {!online && <p className="onm-warn"><WifiOff size={14} /> Reconectando…</p>}
      {fixes.length > 0 && clock < 8 && (
        <p className="onm-warn">
          <Repeat2 size={14} /> Mudança na escalação: {fixes.map((f) => f.inName).filter(Boolean).join(', ')}
        </p>
      )}
      {injuredOff.length > 0 && !ended && (
        <button type="button" className="onm-alert" onClick={() => setPanel('lineup')}>
          <Ambulance size={16} /> {injuredOff.map((p) => p.name).join(', ')} lesionado · substituir
        </button>
      )}
      {applied && now - applied.at < 12000 && <p className="ml-pending"><Repeat2 size={14} /> Ordem dada aos {applied.minute}'</p>}

      <div className="sn-seg ml-tabs" role="tablist">
        {TABS.map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
            {label}
          </button>
        ))}
      </div>

      <div className="ml-body">
        {tab === 'feed' && (
          <ol className="ml-feed" aria-live="polite">
            {feed.length === 0 && <li className="ml-ev k-kickoff">Bola rolando!</li>}
            {feed.map((e) => (
              <li key={e.seq} className={`ml-ev k-${e.kind} ${e.side ? `s-${e.side === side ? 'me' : 'opp'}` : ''} ${MAJOR_EVENTS.has(e.kind) ? 'is-major' : ''}`}>
                <span className="ml-min">{e.minute}'</span>
                {e.side && <OnlineCrest club={e.side === 'h' ? data.home : data.away} size={16} />}
                <span className="ml-txt">{e.kind === 'ft' ? 'Fim de jogo!' : eventText(e, e.side === side ? 'Seu time' : name(e.side))}</span>
              </li>
            ))}
          </ol>
        )}

        {tab === 'stats' && (
          <div className="ml-stats">
            {[
              ['Posse de bola', data.stats?.poss?.[0], data.stats?.poss?.[1], '%'],
              // Finalizações e chutes no gol vêm da súmula do servidor: nos trechos sem ninguém assistindo o motor não grava cada lance.
              ['Finalizações', data.stats?.shots?.[0] ?? live.shots.h, data.stats?.shots?.[1] ?? live.shots.a],
              ['No gol', data.stats?.sot?.[0] ?? live.sot.h, data.stats?.sot?.[1] ?? live.sot.a],
              ['Escanteios', data.stats?.corners?.[0], data.stats?.corners?.[1]],
              ['Faltas', data.stats?.fouls?.[0], data.stats?.fouls?.[1]],
              ['Impedimentos', data.stats?.offsides?.[0], data.stats?.offsides?.[1]],
              ['Amarelos', live.yel.h, live.yel.a],
              ['Vermelhos', live.red.h, live.red.a],
            ].map(([label, h = 0, a = 0, suf = '']) => (
              <div key={label} className="ml-stat">
                <b>{h}{suf}</b>
                <span>
                  <small>{label}</small>
                  <i><em className="h" style={{ width: `${h + a ? (h / (h + a)) * 100 : 50}%` }} /></i>
                </span>
                <b>{a}{suf}</b>
              </div>
            ))}
          </div>
        )}

        {tab === 'ratings' && (
          <div className="ml-ratings">
            {['h', 'a'].map((sd) => (
              <table key={sd} className={`ml-rtable ${sd === side ? 'is-mine' : ''}`}>
                <caption>{name(sd)}</caption>
                <thead><tr><th>Pos</th><th className="left">Jogador</th><th>Nota</th><th>Cond</th></tr></thead>
                <tbody>
                  {players.filter((p) => p.side === sd && p.status !== 'bench').map((p) => (
                    <tr key={p.id} className={`st-${p.status}`}>
                      <td className="pos">{p.pos || p.natural}</td>
                      <td className="left">{p.name}{p.yellow > 0 && <i className="mcard y" />}{p.red > 0 && <i className="mcard r" />}</td>
                      <td>{Number(p.rating).toFixed(1)}</td>
                      <td className={`cond ${condTone(p.cond)}`}>{Math.round(p.cond)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ))}
          </div>
        )}

        {tab === 'lineups' && <div className="onm-lus-tab"><LineupsView fixtureId={data.fixture_id} live /></div>}
      </div>

      {ended ? (
        <div className={`onm-final ${side ? (myGoals > oppGoals ? 'is-win' : myGoals < oppGoals ? 'is-loss' : 'is-draw') : ''}`}>
          <small><Trophy size={13} /> {side ? (myGoals > oppGoals ? 'Vitória' : myGoals < oppGoals ? 'Derrota' : 'Empate') : 'Fim de jogo'}</small>
          <div className="onm-final-score">
            <span><OnlineCrest club={data.home} size={42} /><em>{data.home.short}</em></span>
            <b>{finalH}<i>×</i>{finalA}</b>
            <span><OnlineCrest club={data.away} size={42} /><em>{data.away.short}</em></span>
          </div>
          {data.summary?.pens && <span className="onm-final-pens">Pênaltis {data.summary.pens[0]} – {data.summary.pens[1]}</span>}
          {data.summary?.motm && <span className="onm-final-motm">Melhor em campo · <strong>{data.summary.motm.name}</strong> {Number(data.summary.motm.rating).toFixed(1)}</span>}
          <button type="button" className="gx-btn" onClick={onClose}>Continuar</button>
        </div>
      ) : (
        <>
          {side && (
            <div className="onm-styles" role="group" aria-label="Postura do time">
              {STYLES.map(([id, label, Icon]) => (
                <button key={id} type="button" className={myStyle === id ? 'is-on' : ''} disabled={busy || myStyle === id} onClick={() => apply({ tactics: { style: id } })}>
                  <Icon size={15} /><small>{label}</small>
                </button>
              ))}
            </div>
          )}
          {side && (
            <nav className="ml-quick" aria-label="Ajustes do time">
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setPanel('lineup')}><Users size={16} /> Time</button>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setPanel('tactics')}><ClipboardList size={16} /> Instruções</button>
              <button type="button" className="gx-btn-ghost" onClick={() => setLineups(true)}><Shield size={16} /> Adversário</button>
            </nav>
          )}
          <footer className="ml-ctrl onm-ctrl">
            <span className="onm-real">{phase === 'ht' ? 'Intervalo' : data.home.colors?.stadium || ''}</span>
            <button
              type="button"
              className={`ml-ic ${broadcast ? 'is-on' : ''}`}
              onClick={() => setBroadcast((b) => {
                try { window.localStorage.setItem('sim.broadcast', b ? 'off' : 'on') } catch { /* sem armazenamento */ }
                return !b
              })}
              aria-pressed={broadcast}
              aria-label="Campo 2D"
            >
              <Tv size={18} />
            </button>
          </footer>
        </>
      )}


      {side && !ended && !data.ht_talk?.[side] && data.minute >= 45 && data.minute <= 55 && shownMinute >= 44 && shownMinute <= 46 && (
        <div className="onm-talk" role="dialog" aria-label="Preleção do intervalo">
          <header>
            <Megaphone size={18} />
            <div><small>Intervalo · {data.home.short} {live.sc.h} × {live.sc.a} {data.away.short}</small><strong>O que você diz ao time?</strong></div>
          </header>
          <div className="onm-talk-opts">
            {HT_TALKS.map(([id, label, line]) => (
              <button key={id} type="button" disabled={busy} onClick={() => halftimeTalk(id)}>
                <strong>{label}</strong>
                <span>“{line}”</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {lineups && <LineupsSheet fixtureId={data.fixture_id} live onClose={() => setLineups(false)} />}
      {panel && side && (
        <MatchLineupEditor
          initialView={panel === 'tactics' ? 'tactics' : 'lineup'}
          engineVersion={2}
          catalog={catalog}
          players={players}
          squadById={squadById}
          side={side}
          colors={clubColors(mine)}
          serverFormation={myFormation}
          initialDraft={draftFromMatch(players, side, myFormation)}
          tactics={data.tactics?.[side] || {}}
          maxSubs={data.max_subs ?? 5}
          subsUsed={data.subs?.[side]?.used ?? 0}
          maxWindows={data.max_windows ?? 3}
          windowsUsed={data.subs?.[side]?.windows ?? 0}
          atBreak={data.minute === 45 || data.minute === 90}
          serverMin={data.minute}
          onClose={() => setPanel(false)}
          onApply={({ draft, tactics }) => {
            const base = draftFromMatch(players, side, myFormation)
            const slots = Object.fromEntries(Object.entries(draft.slots).filter(([, pid]) => !draft.injured.includes(pid) || draft.subs.some((x) => x.in === pid)))
            const baseSlots = Object.fromEntries(Object.entries(base.slots).filter(([, pid]) => !base.injured.includes(pid)))
            const changes = {}
            if (draft.subs.length) changes.subs = draft.subs
            if (draft.formation !== myFormation) changes.formation = draft.formation
            if (JSON.stringify(slots) !== JSON.stringify(baseSlots) || changes.formation || changes.subs) changes.slots = slots
            if (JSON.stringify(tactics) !== JSON.stringify(data.tactics?.[side] || {})) changes.tactics = tactics
            setPanel(false)
            if (Object.keys(changes).length) apply(changes)
          }}
        />
      )}
    </div>
  )
}
