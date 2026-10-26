import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Ambulance, ChevronsRight, FastForward, Pause, Play, Repeat2, Settings2, Square, Users } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import MatchLineupEditor, { draftFromMatch } from './MatchLineupEditor'
import useCatalog from '../hooks/useCatalog'
import { fetchSquad, stepMatch } from '../services/managerApi'
import { MAJOR_EVENTS, condTone, eventText, isGoal } from '../utils/managerUtils'
import { COMP_NAME, describeMatch } from '../utils/seasonUtils'
import useMatchAudio from '../../audio/useMatchAudio'

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
export default function MatchLive({ initial, myClub, onFinished, notify }) {
  const { catalog } = useCatalog()
  const [data, setData] = useState(initial)
  const [events, setEvents] = useState(initial.events || [])
  const [clock, setClock] = useState(initial.minute > 0 ? initial.minute : 0)
  const [speed, setSpeed] = useState(1)
  const [paused, setPaused] = useState(false)
  const [busy, setBusy] = useState(false)
  const [overlay, setOverlay] = useState(null) // {kind:'ht'|'injury'|'red'|'et'|'et_ht', minute}
  const [ack, setAck] = useState(null) // parada já vista (minuto)
  const [panel, setPanel] = useState(false)
  const [tab, setTab] = useState('feed')
  const [pending, setPending] = useState(EMPTY)
  const [squadById, setSquadById] = useState(null)
  const [flash, setFlash] = useState(null)
  const [turbo, setTurbo] = useState(false)
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
  const waitingDecision = overlay || panel
  useEffect(() => {
    if (paused || waitingDecision || clock >= serverMin) return undefined
    const id = setInterval(() => setClock((c) => Math.min(serverMin, c + 100 / msPerMin)), 100)
    return () => clearInterval(id)
  }, [paused, waitingDecision, clock, serverMin, msPerMin])

  const shownMinute = Math.floor(clock)
  const visible = useMemo(() => events.filter((e) => e.minute <= shownMinute || (finished && clock >= serverMin)), [events, shownMinute, finished, clock, serverMin])

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
  useMatchAudio({ visible, userSide: side, score: live.sc, minute: shownMinute })

  // GOL! (efeito ao revelar)
  useEffect(() => {
    const g = visible.find((e) => isGoal(e) && !flashed.current.has(e.seq))
    if (!g) return undefined
    flashed.current.add(g.seq)
    if (clock - g.minute > 2) return undefined // retomando partida: sem animação dos gols antigos
    setFlash({ side: g.side, name: g.player_name })
    const t = setTimeout(() => setFlash(null), 1800)
    return () => clearTimeout(t)
  }, [visible, clock])

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
        const r = await stepMatch({
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
        notify?.(e.message, 'alert')
        setPending(EMPTY)
      } finally {
        setBusy(false)
      }
    },
    [busy, finished, pending, data.fixture_id, serverMin, et, notify],
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
    setOverlay(null)
    stopRef.current = null
    setPanel(false)
    setTurbo(true)
    await requestNext({ auto: true })
  }

  // notas por posição do elenco (para o campo do painel mostrar quanto cada um rende em cada vaga)
  useEffect(() => {
    if (!panel || squadById) return
    fetchSquad()
      .then((sq) => setSquadById(Object.fromEntries(sq.players.map((p) => [p.id, p]))))
      .catch(() => setSquadById({}))
  }, [panel, squadById])

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
    <div className="ml" role="dialog" aria-modal="true" aria-label="Partida ao vivo">
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
          ['feed', 'Lances'],
          ['stats', 'Estatísticas'],
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

        {tab === 'lineups' && (
          <div className="ml-lineups">
            {['h', 'a'].map((sd) => (
              <div key={sd} className="ml-lu">
                <h4>
                  <ClubCrest clubId={sd === 'h' ? data.home : data.away} size={18} /> {getClubById(sd === 'h' ? data.home : data.away)?.name}
                  <small>{data.formation?.[sd === 'h' ? 0 : 1]}</small>
                </h4>
                <ul>
                  {players
                    .filter((p) => p.side === sd && p.status !== 'bench')
                    .map((p) => (
                      <li key={p.id} className={`st-${p.status}`}>
                        <span className="ml-pos">{p.pos}</span>
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
            <button type="button" className="ml-team-btn" onClick={() => setPanel(true)} disabled={finished}>
              <Settings2 size={17} /> Time
            </button>
            <button type="button" className="ml-ic" onClick={simulateToEnd} disabled={busy || finished} aria-label="Simular até o fim" title="Simular até o fim (o auxiliar decide)">
              <FastForward size={18} />
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

      {panel && (
        <MatchLineupEditor
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
      )}
    </div>
  )
}
