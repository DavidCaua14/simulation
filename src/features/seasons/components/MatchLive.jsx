import { OpponentTactics } from './OpponentScout'
import { isSessionError } from '../../../lib/sessionRecovery'
import { Suspense, lazy, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Ambulance, ChevronsRight, ClipboardList, FastForward, Flag, Pause, Play, Repeat2, Settings2, Square, Tv, Users } from 'lucide-react'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import PlayerSheet from './PlayerSheet'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import MatchLineupEditor, { draftFromMatch } from './MatchLineupEditor'
import { renderSeasonPitchCard } from './renderSeasonPitchCard'
import { PitchTokenContext } from './pitchToken'
import FunctionsPanel from '../matchflow/FunctionsPanel'
import useCatalog from '../hooks/useCatalog'
import { fetchPlayer, fetchSquad, stepMatch } from '../services/managerApi'
import { MAJOR_EVENTS, condTone, eventText, isGoal } from '../utils/managerUtils'
import { COMP_NAME, describeMatch } from '../utils/seasonUtils'
import useMatchAudio from '../../audio/useMatchAudio'
import { HOLD_KINDS } from '../../match2d/director'

// Transmissão 3D: carregada só quando ligada, para o Three.js não pesar na abertura do jogo
const MatchBroadcast3D = lazy(() => import('../../match3d/MatchBroadcast3D'))

const SPEEDS = [
  { id: 1, label: '1x', ms: 700 },
  { id: 2, label: '2x', ms: 330 },
  { id: 4, label: '4x', ms: 140 },
]
const EMPTY = { subs: [], tactics: null, formation: null, slots: null, draft: null }
const SEG = 5 // minutos por etapa simulada no servidor
const STOPS = new Set(['ht', 'injury', 'red', 'et', 'et_ht'])
const SHOT_KINDS = new Set(['goal', 'pen_goal', 'save', 'shot_off', 'pen_miss'])

function nextTarget(minute, et) {
  if (minute < 45) return Math.min(45, minute + SEG)
  if (minute < 90) return Math.min(90, minute + SEG)
  return et ? Math.min(120, minute + SEG) : 90
}

// PARTIDA AO VIVO: o motor simula em etapas de 5 minutos no servidor; a tela revela os lances com o relógio.
// Mudanças (substituições, postura, formação) entram na PRÓXIMA etapa — e só afetam o que vem depois.
// api / catalog (opcionais): substituem o servidor e as formações do banco — usados pelo laboratório local (#lab3d).
export default function MatchLive({ initial, myClub, onFinished, notify, api, catalog: catalogProp }) {
  const { catalog: loadedCatalog } = useCatalog()
  const catalog = catalogProp || loadedCatalog
  const [data, setData] = useState(initial)
  const [events, setEvents] = useState(initial.events || [])
  const [clock, setClock] = useState(initial.minute > 0 ? initial.minute : 0)
  const [speed, setSpeed] = useState(1)
  const [paused, setPaused] = useState(false)
  const [busy, setBusy] = useState(false)
  const [overlay, setOverlay] = useState(null) // {kind:'ht'|'injury'|'red'|'et'|'et_ht', minute}
  const [ack, setAck] = useState(null) // parada já vista (minuto)
  const [panel, setPanel] = useState(false)
  const [roles, setRoles] = useState(false)
  const [tab, setTab] = useState('feed')
  const [pending, setPending] = useState(EMPTY)
  const [squadById, setSquadById] = useState(null)
  const [playerInfo, setPlayerInfo] = useState(null)
  const [flash, setFlash] = useState(null)
  const [turbo, setTurbo] = useState(false)
  const [holdAt, setHoldAt] = useState(null) // minuto de um lance que a transmissão ainda está mostrando
  // lances que o campo já mostrou (gol na rede, defesa, cartão): entram no placar e no relato na hora,
  // mesmo com o relógio esperando outro lance do mesmo minuto
  // lances que já estavam no relato ao abrir a partida (retomada) não são reencenados nem esperados
  const [revealed, setRevealed] = useState(() => new Set((initial.events || []).filter((e) => e.minute < (initial.minute > 0 ? initial.minute : 0) - 0.5).map((e) => e.seq)))
  const onReveal = useCallback((seqs) => {
    setRevealed((prev) => {
      const next = new Set(prev)
      for (const s of seqs) next.add(s)
      return next
    })
  }, [])
  // Campo 3D (padrão) ou só placar — preferência só deste navegador
  const [broadcast, setBroadcast] = useState(() => {
    try {
      return window.localStorage.getItem('sim.broadcast') !== 'off'
    } catch {
      return true
    }
  })
  const toggleBroadcast = () => {
    // ao ligar o campo no meio do jogo, o que já passou no relógio fica como mostrado (o campo não reencena)
    if (!broadcast) onReveal(events.filter((e) => e.minute < clock - 0.5).map((e) => e.seq))
    setBroadcast((b) => {
      try {
        window.localStorage.setItem('sim.broadcast', b ? 'off' : 'on')
      } catch {
        /* sem armazenamento: vale só nesta partida */
      }
      return !b
    })
  }
  // o aparelho não abriu o 3D (sem WebGL): a partida segue só no placar
  const [fieldFailed, setFieldFailed] = useState(false)
  const lastSeq = useRef(Math.max(0, ...(initial.events || []).map((e) => e.seq)))
  const flashed = useRef(new Set())
  const stopRef = useRef(null)

  const side = data.user_side
  const oside = side === 'h' ? 'a' : 'h'
  const home = getClubById(data.home)
  const away = getClubById(data.away)
  const finished = data.status === 'finished'
  const serverMin = data.minute
  const et = Boolean(data.et)

  // ---- relógio ----
  const msPerMin = turbo ? 35 : SPEEDS.find((s) => s.id === speed).ms
  const waitingDecision = overlay || panel || playerInfo
  // UMA fonte de lances (events) e UM relógio (clock). Com o campo na tela, finalização, cartão e impedimento só
  // entram no relato, no placar e no som quando o campo os MOSTRA (revealed); o relógio espera por eles.
  const fieldOn = broadcast && !turbo && !fieldFailed && Boolean(catalog)
  const pendingHold = useMemo(() => {
    if (!fieldOn) return null
    let m = null
    for (const e of events) if (HOLD_KINDS.has(e.kind) && !revealed.has(e.seq)) m = m == null ? e.minute : Math.min(m, e.minute)
    return m
  }, [fieldOn, events, revealed])
  const capMinute = fieldOn ? [holdAt, pendingHold].filter((v) => v != null).reduce((a, b) => Math.min(a, b), Infinity) : Infinity
  useEffect(() => {
    if (paused || waitingDecision || clock >= serverMin) return undefined
    // o relógio não passa do lance que o campo ainda vai mostrar (nem do que está mostrando)
    const cap = Number.isFinite(capMinute) ? Math.max(clock, capMinute - 0.01) : Infinity
    if (clock >= cap) return undefined
    const id = setInterval(() => setClock((c) => Math.min(serverMin, cap, c + 100 / msPerMin)), 100)
    return () => clearInterval(id)
  }, [paused, waitingDecision, clock, serverMin, msPerMin, capMinute])
  // segurança: se o campo não mostrar um lance em 40 s (aba em segundo plano, aparelho lento), o relato segue
  useEffect(() => {
    if (!fieldOn || paused || waitingDecision || pendingHold == null || clock < pendingHold - 0.02) return undefined
    const t = setTimeout(() => onReveal(events.filter((e) => HOLD_KINDS.has(e.kind) && e.minute <= pendingHold).map((e) => e.seq)), 40000)
    return () => clearTimeout(t)
  }, [fieldOn, paused, waitingDecision, pendingHold, clock, events, onReveal])
  // a transmissão recebe os lances 1 minuto antes, para montar a jogada desde onde a bola está
  const upcoming = useMemo(() => events.filter((e) => e.minute <= Math.floor(clock) + 1), [events, clock])

  const shownMinute = Math.floor(clock)
  const visible = useMemo(
    () =>
      events.filter((e) => {
        if (revealed.has(e.seq) || (finished && clock >= serverMin)) return true
        if (fieldOn && HOLD_KINDS.has(e.kind)) return false // só depois de aparecer em campo
        return e.minute <= shownMinute
      }),
    [events, shownMinute, revealed, finished, clock, serverMin, fieldOn],
  )

  // placar e números a partir dos lances JÁ mostrados (sem spoiler)
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

  // som sincronizado com os lances revelados (apitos, gols, cartões, torcida)
  // com o campo ligado (e sem pular para o fim), contatos e apitos saem do campo no instante visual
  useMatchAudio({ visible, userSide: side, score: live.sc, minute: shownMinute, field: fieldOn })

  // GOL! (efeito ao revelar)
  useEffect(() => {
    const g = visible.find((e) => isGoal(e) && !flashed.current.has(e.seq))
    if (!g) return undefined
    flashed.current.add(g.seq)
    if (clock - g.minute > 2) return undefined // retomando partida: sem animação dos gols antigos
    if (fieldOn) return undefined // a transmissão mostra o gol em campo
    setFlash({ side: g.side, name: g.player_name })
    const t = setTimeout(() => setFlash(null), 1800)
    return () => clearTimeout(t)
  }, [visible, clock, fieldOn])

  // ---- etapa no servidor ----
  const requestNext = useCallback(
    async ({ auto = false } = {}) => {
      if (busy || finished) return
      setBusy(true)
      const changes = {}
      if (pending.subs.length) changes.subs = pending.subs
      if (pending.tactics) changes.tactics = pending.tactics
      if (pending.formation) changes.formation = pending.formation
      if (pending.slots) changes.slots = pending.slots
      try {
        const r = await (api?.stepMatch || stepMatch)({
          fixtureId: data.fixture_id,
          from: serverMin,
          to: auto ? 120 : nextTarget(serverMin, et),
          changes: Object.keys(changes).length ? changes : null,
          auto,
          afterSeq: lastSeq.current,
        })
        setEvents((prev) => {
          const seen = new Set(prev.map((e) => e.seq))
          const add = (r.events || []).filter((e) => !seen.has(e.seq))
          if (add.length) lastSeq.current = Math.max(lastSeq.current, ...add.map((e) => e.seq))
          return [...prev, ...add]
        })
        setData(r)
        setPending(EMPTY)
        stopRef.current = STOPS.has(r.stop) ? { kind: r.stop, minute: r.minute } : null
      } catch (e) {
        if (isSessionError(e)) return
        notify?.(e.message, 'alert')
        setPending(EMPTY)
        // o relógio pede a etapa de novo assim que fica livre: espera um pouco para não repetir em sequência
        await new Promise((resolve) => setTimeout(resolve, 3000))
      } finally {
        setBusy(false)
      }
    },
    [busy, finished, pending, data.fixture_id, serverMin, et, notify, api],
  )

  // quando o relógio alcança o servidor: para nas decisões (intervalo, lesão, expulsão) ou pede a próxima etapa
  useEffect(() => {
    if (busy || paused || panel || overlay || clock < serverMin) return
    const stop = stopRef.current
    if (stop && ack !== stop.minute + stop.kind) {
      setOverlay(stop)
      return
    }
    if (!finished) requestNext()
  }, [clock, serverMin, busy, paused, panel, overlay, finished, ack, requestNext])

  const continueFromStop = () => {
    if (overlay) setAck(overlay.minute + overlay.kind)
    stopRef.current = null
    setOverlay(null)
  }

  async function simulateToEnd() {
    setPaused(false)
    setOverlay(null)
    stopRef.current = null
    setPanel(false)
    setTurbo(true)
    await requestNext({ auto: true })
  }

  // notas por posição do elenco (para o campo do painel mostrar quanto cada um rende em cada vaga)
  useEffect(() => {
    if (!panel || squadById) return
    const load = api?.fetchSquad || fetchSquad
    load()
      .then((sq) => setSquadById(Object.fromEntries(sq.players.map((p) => [p.id, p]))))
      .catch(() => setSquadById({}))
  }, [panel, squadById, api])

  // ---- jogadores ----
  const players = data.players || []
  const subsUsed = data.subs?.[side]?.used ?? 0
  const windowsUsed = data.subs?.[side]?.windows ?? 0
  const atBreak = serverMin === 45 || serverMin === 90
  const myFormation = data.formation?.[side === 'h' ? 0 : 1]
  const myTactics = { ...(data.tactics?.[side] || {}), ...(pending.tactics || {}) }
  const injuredOff = players.filter((p) => p.side === side && p.status === 'injured_off' && p.slot)

  const homeIsMine = side === 'h'
  const clockLabel = finished && clock >= serverMin ? 'FIM' : overlay?.kind === 'ht' ? 'INT' : `${Math.min(shownMinute, et ? 120 : 90)}'`
  const feed = [...visible].reverse()

  return (
    <div className={`ml ${fieldOn ? 'has-broadcast' : ''}`} role="dialog" aria-modal="true" aria-label="Partida ao vivo">
      {broadcast && !fieldFailed && catalog && (
        <div className="ml-stage">
          <Suspense fallback={<div className="m3d-boot">Carregando o estádio…</div>}>
            <MatchBroadcast3D
              data={data}
              catalog={catalog}
              clock={clock}
              minute={shownMinute}
              events={upcoming}
              onHold={setHoldAt}
              onReveal={onReveal}
              onUnavailable={() => setFieldFailed(true)}
              paused={paused || Boolean(waitingDecision) || clock >= serverMin}
              speed={turbo ? 4 : speed}
              score={live.sc}
              finished={finished && clock >= serverMin}
              clockLabel={clockLabel}
              userSide={side}
            />
          </Suspense>
        </div>
      )}
      <header className="ml-top" style={{ '--hc': home?.colors?.[0] || '#1b3566', '--ac': away?.colors?.[0] || '#5a1b1b' }}>
        <div className="ml-comp">
          <CompEmblem comp={data.competition} size={18} />
          <span>{COMP_NAME[data.competition]}</span>
          <em>{describeMatch({ stage: data.stage, round: data.round, leg: data.leg, group: data.group })}</em>
          <span className={`pm-live ${finished && clock >= serverMin ? 'is-done' : ''}`}>{finished && clock >= serverMin ? 'Encerrado' : 'Ao vivo'}</span>
        </div>
        <div className="ml-board">
          <div className={`ml-team ${homeIsMine ? 'is-mine' : ''}`}>
            <ClubCrest clubId={data.home} size={48} />
            <b>{home?.short || home?.name}</b>
          </div>
          <div className="ml-score">
            <span className="ml-goals">
              <b key={`h${live.sc.h}`}>{live.sc.h}</b>
              <i>:</i>
              <b key={`a${live.sc.a}`}>{live.sc.a}</b>
            </span>
            <span className="ml-clock">{clockLabel}</span>
            {live.so && (
              <small className="ml-pens">
                Pênaltis {live.pens.h} – {live.pens.a}
              </small>
            )}
            {data.decisive && data.agg && (data.agg[0] > 0 || data.agg[1] > 0) && data.stage !== 'final' && (
              <small className="ml-agg">
                Agregado {live.sc.h + data.agg[0]} – {live.sc.a + data.agg[1]}
              </small>
            )}
          </div>
          <div className={`ml-team ${!homeIsMine ? 'is-mine' : ''}`}>
            <ClubCrest clubId={data.away} size={48} />
            <b>{away?.short || away?.name}</b>
          </div>
        </div>
        <div className="ml-progress" aria-hidden="true">
          <i style={{ width: `${(Math.min(clock, et ? 120 : 90) / (et ? 120 : 90)) * 100}%` }} />
        </div>
      </header>

      <div className="sn-seg ml-tabs" role="tablist">
        {[
          ['feed', 'Ação'],
          ['stats', 'Est. da partida'],
          ['ratings', 'Classif.'],
          ['lineups', 'Times'],
        ].map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
            {label}
          </button>
        ))}
      </div>

      <div className="ml-body">
        {tab === 'feed' && (
          <ol className="ml-feed" aria-live="polite">
            {feed.length === 0 && <li className="ml-ev k-kickoff">Os times entram em campo…</li>}
            {feed.map((e) => (
              <li key={e.seq} className={`ml-ev k-${e.kind} ${e.side ? `s-${e.side === side ? 'me' : 'opp'}` : ''} ${MAJOR_EVENTS.has(e.kind) ? 'is-major' : ''}`}>
                <span className="ml-min">{e.kind === 'kickoff' ? '0' : e.minute}'</span>
                {e.side && <ClubCrest clubId={e.side === 'h' ? data.home : data.away} size={16} />}
                <span className="ml-txt">{eventText(e, e.side === side ? 'Seu time' : 'Adversário')}</span>
              </li>
            ))}
          </ol>
        )}

        {tab === 'stats' && (
          <div className="ml-stats">
            {[
              ['Posse de bola', data.stats?.poss?.[0], data.stats?.poss?.[1], '%'],
              ['Finalizações', live.shots.h, live.shots.a],
              ['No gol', live.sot.h, live.sot.a],
              ['Escanteios', data.stats?.corners?.[0], data.stats?.corners?.[1]],
              ['Faltas', data.stats?.fouls?.[0], data.stats?.fouls?.[1]],
              ['Impedimentos', data.stats?.offsides?.[0], data.stats?.offsides?.[1]],
              ['Amarelos', live.yel.h, live.yel.a],
              ['Vermelhos', live.red.h, live.red.a],
            ].map(([label, h = 0, a = 0, suf = '']) => (
              <div key={label} className="ml-stat">
                <b>
                  {h}
                  {suf}
                </b>
                <span>
                  <small>{label}</small>
                  <i>
                    <em className="h" style={{ width: `${h + a ? (h / (h + a)) * 100 : 50}%` }} />
                  </i>
                </span>
                <b>
                  {a}
                  {suf}
                </b>
              </div>
            ))}
          </div>
        )}

        {data.engine_version === 1 && <p className="sn-hint">Esta partida começou antes da atualização e mantém as regras de simulação anteriores até terminar.</p>}
        {tab === 'ratings' && (
          <div className="ml-ratings">
            {['h', 'a'].map((sd) => (
              <table key={sd} className={`ml-rtable ${sd === side ? 'is-mine' : ''}`}>
                <caption>{getClubById(sd === 'h' ? data.home : data.away)?.name}</caption>
                <thead>
                  <tr>
                    <th>Pos</th>
                    <th className="left">Jogador</th>
                    <th>Clas</th>
                    <th>Cond</th>
                  </tr>
                </thead>
                <tbody>
                  {players
                    .filter((p) => p.side === sd && p.status !== 'bench')
                    .map((p) => (
                      <tr key={p.id} className={`st-${p.status}`}>
                        <td className="pos">{p.pos || p.natural}</td>
                        <td className="left">
                          {p.name}
                          {p.yellow > 0 && <i className="mcard y" />}
                          {p.red > 0 && <i className="mcard r" />}
                        </td>
                        <td>{Number(p.rating).toFixed(1)}</td>
                        <td className={`cond ${condTone(p.cond)}`}>{Math.round(p.cond)}%</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            ))}
          </div>
        )}

        {tab === 'lineups' && (
          <div className="ml-lineups">
            {['h', 'a'].map((sd) => (
              <div key={sd} className="ml-lu">
                <h4>
                  <ClubCrest clubId={sd === 'h' ? data.home : data.away} size={18} /> {getClubById(sd === 'h' ? data.home : data.away)?.name}
                  <small>{data.formation?.[sd === 'h' ? 0 : 1]}</small>
                </h4>
                {sd === oside && <OpponentTactics formation={data.formation?.[sd === 'h' ? 0 : 1]} tactics={data.tactics?.[sd]} live />}
                <ul>
                  {players
                    .filter((p) => p.side === sd && p.status !== 'bench')
                    .map((p) => (
                      <li key={p.id} className={`st-${p.status}`}>
                        <button type="button" className="ml-base-button" aria-label={`Ver ficha de ${p.name}`} onClick={async () => {
                          const clubId = sd === 'h' ? data.home : data.away
                          try {
                            const detail = await fetchPlayer(p.id, data.fixture_id)
                            if (detail) setPlayerInfo({ ...detail, club_id: clubId, condition: Math.round(p.cond) })
                          } catch (error) { if (!isSessionError(error)) notify?.(error.message, 'alert') }
                        }}><BasePlayerCard player={{ ...p, club_id: sd === 'h' ? data.home : data.away }} position={p.pos || p.natural} width={54} /></button>
                        <span className="ml-pn">
                          {p.name}
                          {p.yellow > 0 && <i className="mcard y" />}
                          {p.red > 0 && <i className="mcard r" />}
                          {p.injured && <Ambulance size={11} />}
                        </span>
                        <span className={`ml-cond ${condTone(p.cond)}`}>
                          <i style={{ width: `${p.cond}%` }} />
                        </span>
                        <b className="ml-rt">{Number(p.rating).toFixed(1)}</b>
                      </li>
                    ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </div>

      {(pending.subs.length > 0 || pending.tactics || pending.formation || pending.slots) && !finished && (
        <p className="ml-pending">
          <Repeat2 size={14} /> Mudanças entram a partir do {serverMin}' {busy ? '(aplicando…)' : ''}
        </p>
      )}

      {!(finished && clock >= serverMin) && (
        <nav className="ml-quick" aria-label="Ajustes do time">
          <button type="button" className="gx-btn-ghost" disabled={finished} onClick={() => setPanel('lineup')}>
            <Users size={16} /> Formação
          </button>
          <button type="button" className="gx-btn-ghost" disabled={finished} onClick={() => setPanel('tactics')}>
            <ClipboardList size={16} /> Instruções
          </button>
          <button type="button" className="gx-btn-ghost" disabled={finished} onClick={() => setRoles(true)}>
            <Flag size={16} /> Funções
          </button>
        </nav>
      )}

      <footer className="ml-ctrl">
        {finished && clock >= serverMin ? (
          <button type="button" className="gx-btn" onClick={() => onFinished(data.summary)}>
            Ver resumo da partida <ChevronsRight size={18} />
          </button>
        ) : (
          <>
            <button type="button" className="ml-ic" onClick={() => setPaused((p) => !p)} aria-label={paused ? 'Continuar' : 'Pausar'}>
              {paused ? <Play size={18} fill="currentColor" /> : <Pause size={18} fill="currentColor" />}
            </button>
            <div className="ml-speed" role="radiogroup" aria-label="Velocidade">
              {SPEEDS.map((s) => (
                <button key={s.id} type="button" role="radio" aria-checked={speed === s.id && !turbo} className={speed === s.id && !turbo ? 'is-on' : ''} onClick={() => setSpeed(s.id)}>
                  {s.label}
                </button>
              ))}
            </div>
            <button type="button" className="ml-team-btn" onClick={() => setPanel('lineup')} disabled={finished}>
              <Settings2 size={17} /> Time
            </button>
            <button type="button" className="ml-ic" onClick={simulateToEnd} disabled={busy || finished} aria-label="Simular até o fim" title="Simular até o fim (o auxiliar decide)">
              <FastForward size={18} />
            </button>
            <button
              type="button"
              className={`ml-ic ${fieldOn ? 'is-on' : ''}`}
              onClick={toggleBroadcast}
              disabled={fieldFailed}
              aria-pressed={broadcast}
              aria-label={broadcast ? 'Ver só o placar' : 'Ver o jogo em 3D'}
              title={fieldFailed ? 'Este aparelho não abre o 3D: só placar' : broadcast ? 'Só placar' : 'Jogo em 3D'}
            >
              <Tv size={18} />
            </button>
          </>
        )}
      </footer>

      {flash && (
        <div className={`ml-flash ${flash.side === side ? 'is-me' : 'is-opp'}`} aria-hidden="true">
          <b>GOOOL!</b>
          <span>{flash.name}</span>
        </div>
      )}

      {overlay && !panel && (
        <div className="ml-ov">
          <div className="ml-ov-card">
            {overlay.kind === 'ht' && (
              <>
                <small>Intervalo</small>
                <h3>
                  {home?.name} {live.sc.h} × {live.sc.a} {away?.name}
                </h3>
                <p>
                  Finalizações {live.shots.h} × {live.shots.a} · posse {data.stats?.poss?.[0]}% × {data.stats?.poss?.[1]}%. Hora de mexer no time (as substituições
                  no intervalo não gastam parada).
                </p>
              </>
            )}
            {overlay.kind === 'injury' && (
              <>
                <small>Lesão no seu time</small>
                <h3>
                  <Ambulance size={18} /> {injuredOff.map((p) => p.name).join(', ') || 'Jogador lesionado'}
                </h3>
                <p>Escolha o substituto. Se você continuar sem trocar, o auxiliar faz a troca (se ainda houver substituições).</p>
              </>
            )}
            {overlay.kind === 'red' && (
              <>
                <small>Expulsão</small>
                <h3>
                  <Square size={16} className="ml-redcard" /> Seu time está com um a menos
                </h3>
                <p>Reorganize: mude a formação ou recue a postura para segurar o resultado.</p>
              </>
            )}
            {(overlay.kind === 'et' || overlay.kind === 'et_ht') && (
              <>
                <small>{overlay.kind === 'et' ? 'Prorrogação' : 'Intervalo da prorrogação'}</small>
                <h3>Mais 30 minutos!</h3>
                <p>O cansaço pesa. Use as substituições que restam.</p>
              </>
            )}
            <div className="ml-ov-actions">
              <button type="button" className="gx-btn-ghost" onClick={() => setPanel(true)}>
                <Users size={16} /> Ajustar time
              </button>
              <button type="button" className="gx-btn" onClick={continueFromStop}>
                Continuar <Play size={16} fill="currentColor" />
              </button>
            </div>
          </div>
        </div>
      )}

      {roles && (
        <div className="ml-roles">
          <FunctionsPanel notify={notify} onDone={() => setRoles(false)} />
        </div>
      )}

      {playerInfo && <PlayerSheet player={playerInfo} onClose={() => setPlayerInfo(null)} />}

      {panel && (
        <PitchTokenContext.Provider value={renderSeasonPitchCard}>
        <MatchLineupEditor
          initialView={panel === 'tactics' ? 'tactics' : 'lineup'}
          engineVersion={data.engine_version ?? 1}
          catalog={catalog}
          players={players}
          squadById={squadById}
          side={side}
          colors={getClubById(myClub)?.colors || (side === 'h' ? home : away)?.colors}
          serverFormation={myFormation}
          initialDraft={pending.draft || draftFromMatch(players, side, myFormation)}
          tactics={myTactics}
          maxSubs={data.max_subs ?? 5}
          subsUsed={subsUsed}
          maxWindows={data.max_windows ?? 3}
          windowsUsed={windowsUsed}
          atBreak={atBreak}
          serverMin={serverMin}
          onClose={() => setPanel(false)}
          onApply={({ draft, tactics }) => {
            const base = draftFromMatch(players, side, myFormation)
            const slots = Object.fromEntries(Object.entries(draft.slots).filter(([, pid]) => !draft.injured.includes(pid) || draft.subs.some((x) => x.in === pid)))
            const slotsChanged = JSON.stringify(slots) !== JSON.stringify(Object.fromEntries(Object.entries(base.slots).filter(([, pid]) => !base.injured.includes(pid))))
            const tacChanged = JSON.stringify(tactics) !== JSON.stringify(data.tactics?.[side] || {})
            setPending({
              subs: draft.subs,
              formation: draft.formation !== myFormation ? draft.formation : null,
              slots: slotsChanged || draft.formation !== myFormation || draft.subs.length ? slots : null,
              tactics: tacChanged ? tactics : null,
              draft,
            })
            setPanel(false)
          }}
        />
        </PitchTokenContext.Provider>
      )}
    </div>
  )
}
