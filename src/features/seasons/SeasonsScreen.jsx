import { isSessionError } from '../../lib/sessionRecovery'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { getClubById } from '../club/data/clubs'
import useManagerData from './hooks/useManagerData'
import useCountdown from './hooks/useCountdown'
import { createWorldSimulation } from './utils/worldSimulation'
import { advanceWorld, dateLabel, requestId } from './services/careerWorldApi'
import WorldPanel from './world/WorldPanel'
import { advanceDays, fetchHub, markMessagesRead, resign, respondOffer, startMatch, startNextSeason } from './services/managerApi'
import { flattenFixtures, playerHistory, projectCalendar } from './utils/seasonSelectors'
import { msgCategory } from './utils/managerUtils'
import { formatRemaining } from './utils/seasonUtils'
import SeasonHeader from './ui/SeasonHeader'
import { ErrorState, LoadingState } from './ui/States'
import BottomNav from './components/BottomNav'
import PostMatch from './components/PostMatch'
import MatchLive from './components/MatchLive'
import PreMatch from './components/PreMatch'
import MatchReport from './components/MatchReport'
import ParallelDigest from './components/ParallelDigest'
import InboxSheet from './components/InboxSheet'
import '../cards/cards.css'
import HomeTab from './tabs/HomeTab'
import TeamTab from './tabs/TeamTab'
import MatchesTab from './tabs/MatchesTab'
import CompetitionsTab from './tabs/CompetitionsTab'
import CareerTab from './tabs/CareerTab'
import './seasons.css'
import './manager.css'

const TITLES = { home: 'Início', team: 'Time', matches: 'Jogos', comps: 'Torneios', career: 'Carreira', world: 'Mundo' }

// MODO CARREIRA (treinador): você comanda um clube real. Tudo é decidido no banco (supabase/manager/*.sql);
// O avanço até a próxima partida processa as competições paralelas no mesmo calendário.
export default function SeasonsScreen({ onBack }) {
  const { hub, byComp, loading, error, refresh } = useManagerData()
  const [tab, setTab] = useState('home')
  const [careerView, setCareerView] = useState(null)
  const [compSel, setCompSel] = useState(null)
  const [busy, setBusy] = useState(null) // 'start' | 'advance' | 'next' | 'resign' | 'offer:<id>'
  const [live, setLive] = useState(null) // payload da partida ao vivo
  const [summary, setSummary] = useState(null) // pós-jogo
  const [preMatch, setPreMatch] = useState(null) // id da partida no pré-jogo (escalações e análise do rival)
  const [digest, setDigest] = useState(null)
  const [report, setReport] = useState(null)
  const [inbox, setInbox] = useState(null)
  const [worldArea, setWorldArea] = useState('news')
  const [teamFocus, setTeamFocus] = useState(null)
  const [toast, setToast] = useState(null)

  const actionLock = useRef(false)
  const mounted = useRef(true)
  useEffect(() => { mounted.current = true; return () => { mounted.current = false } }, [])
  const simulation = useMemo(() => createWorldSimulation({ advance: advanceWorld, refresh, peek: () => fetchHub(), requestId }), [refresh])
  const [prepareProgress, setPrepareProgress] = useState(null)
  const onPrepareProgress = useCallback((h, r) => mounted.current && setPrepareProgress(dateLabel(r?.today || h?.world?.today)), [])
  const worldStatus = busy === 'prepare' || busy === 'next' ? 'syncing' : 'idle'

  const notify = useCallback((text, kind = 'info', action = null) => setToast({ text, kind, action, id: Date.now() }), [])
  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), toast.action ? 7000 : 4200)
    return () => clearTimeout(t)
  }, [toast])

  // Proposta, resposta de negociação ou proposta de trabalho nova: alerta na hora, com atalho para a mensagem.
  const lastMsg = useRef(null)
  useEffect(() => {
    if (!hub?.messages) return
    const top = hub.messages.reduce((mx, m) => Math.max(mx, m.id), 0)
    if (lastMsg.current == null) {
      lastMsg.current = top
      return
    }
    const fresh = hub.messages.filter((m) => m.id > lastMsg.current && !m.read && ['market', 'career'].includes(msgCategory(m)))
    lastMsg.current = Math.max(lastMsg.current, top)
    if (fresh.length) {
      const first = fresh[fresh.length - 1]
      notify(fresh.length === 1 ? first.title : `${fresh.length} novas mensagens: ${first.title}`, 'offer', () => setInbox({ focusId: fresh.length === 1 ? first.id : null, category: msgCategory(first) }))
    }
  }, [hub, notify])

  const remaining = useCountdown(hub?.career.next_reset_at, () => refresh({ silent: true }))

  // ---- dados derivados (em memória) ----
  const derived = useMemo(() => {
    if (!hub) return null
    const myClub = hub.coach.club_id
    const flat = flattenFixtures(byComp)
    return { myClub, flat, calendar: projectCalendar(byComp, myClub, 14), history: playerHistory(flat), nextEvent: hub.next_event }
  }, [hub, byComp])

  const finished = hub?.season.status === 'finished'
  const hasEnergy = hub ? hub.career.energy + hub.career.bonus_energy > 0 : false
  const calendarReady = !hub?.world || (!hub.world.needs_sync && !(hub.next_event?.days_until > 0))
  const canPlay = calendarReady && (hasEnergy || Boolean(hub?.live_match)) && !finished && !busy && worldStatus !== 'syncing'
  const blockedText = worldStatus === 'syncing' ? 'Preparando a próxima partida…' : finished ? 'Temporada encerrada' : remaining != null ? `Sem energia · recarga em ${formatRemaining(remaining)}` : 'Sem energia'

  const goTab = useCallback((id, sub = null) => {
    setTeamFocus(null)
    setTab(id)
    if (id === 'career') setCareerView(sub)
  }, [])

  // ---- ações ----
  async function run(kind, fn) {
    if (actionLock.current) return null
    actionLock.current = true
    setBusy(kind)
    try {
      return await fn()
    } catch (e) {
      if (isSessionError(e)) return null
      notify(e.message, 'alert')
      refresh({ silent: true })
      return null
    } finally {
      actionLock.current = false
      if (mounted.current) setBusy(null)
    }
  }

  const prepareNext = () => run('prepare', async () => {
    try {
      const next = await simulation.prepare(hub, { isActive: () => mounted.current, onProgress: onPrepareProgress })
      if (next && next.season.status === 'finished') notify('Temporada encerrada. Veja o balanço no Início.', 'ok')
    } finally {
      if (mounted.current) setPrepareProgress(null)
    }
  })

  const play = () =>
    run('start', async () => {
      if (hub.world && !hub.live_match) {
        const ready = await simulation.prepare(hub, { isActive: () => mounted.current })
        if (!ready || ready.season.status === 'finished' || ready.coach.status !== 'employed') return
      }
      const p = await startMatch() // idempotente: retoma a partida em andamento sem cobrar energia de novo
      setPreMatch(null)
      setLive(p)
      refresh({ silent: true })
    })

  function onMatchFinished(s) {
    setLive(null)
    setSummary(s)
    refresh({ silent: true })
  }

  const advance = (untilOffer) =>
    run('advance', async () => {
      const d = await advanceDays(untilOffer)
      setDigest(d)
      refresh({ silent: true })
      if (d.more) notify('Avançamos o máximo possível de uma vez. Toque em avançar de novo para continuar.', 'info')
    })

  const respond = (offerId, accept) =>
    run(`offer:${offerId}`, async () => {
      const r = await respondOffer(offerId, accept)
      await refresh({ silent: true })
      if (r.accepted) {
        notify(`Contrato assinado! Você é o novo treinador: ${getClubById(r.club_id)?.name}. A temporada segue de onde parou.`, 'ok')
        setTab('home')
      } else notify('Proposta recusada.', 'info')
    })

  const startNext = () =>
    run('next', async () => {
      if (hub.world) {
        const ready = await simulation.prepare(hub, { isActive: () => mounted.current })
        if (!ready) return
      }
      await startNextSeason()
      await refresh({ silent: true })
      setTab('home')
      notify('Nova temporada! Calendário e objetivos atualizados.', 'ok')
    })

  const doResign = () =>
    run('resign', async () => {
      await resign()
      await refresh({ silent: true })
      setTab('home')
      notify('Você deixou o clube. Avance os dias para receber propostas.', 'info')
    })

  const openInbox = (focus = null) => setInbox({ focusId: typeof focus === 'number' ? focus : null, category: typeof focus === 'string' ? focus : 'all' })
  const seenInbox = (ids) => {
    if (ids?.length) markMessagesRead(ids).then(() => refresh({ silent: true })).catch(() => {})
  }
  // Atalho de cada mensagem: leva à tela onde a decisão é tomada.
  const inboxAction = (m) => {
    setInbox(null)
    if (m.action === 'open_negotiations' || m.action === 'open_finance') {
      setWorldArea(m.action === 'open_finance' ? 'finance' : 'deals')
      setTab('world')
    } else if (m.action === 'open_player') {
      setTeamFocus(m.player_id || null)
      setTab('team')
    } else if (m.action === 'open_offers') goTab('career', 'offers')
  }

  // Voltar (topo) sempre leva ao Início do modo, fechando o que estiver aberto; sair do modo tem botão próprio.
  const atHome = tab === 'home' && !preMatch && !report && !inbox && !digest && !summary
  const goHome = () => {
    setPreMatch(null)
    setReport(null)
    setInbox(null)
    setCompSel(null)
    setTab('home')
  }

  const actions = {
    exit: onBack,
    refresh: () => refresh({ silent: true }),
    play,
    // Dia de jogo: abre o pré-jogo; a partida (e o gasto de energia) só começa em "Iniciar partida"
    openPreMatch: () => setPreMatch(hub?.next_event?.fixture_id ?? null),
    prepareNext,
    advance,
    startNext,
    goTab,
    openInbox,
    respondOffer: respond,
    resign: doResign,
    openReport: (f) => setReport(typeof f === 'number' ? f : f.id),
    openComp: (id) => {
      setCompSel(id)
      setTab('comps')
    },
  }

  const ctx = hub && derived ? { hub, byComp, ...derived, canPlay, blockedText, busy: busy || (worldStatus === 'syncing' ? 'world' : null), worldStatus, prepareProgress } : null
  const badges = hub ? { career: hub.offers.length, home: hub.unread > 0 ? hub.unread : 0, team: hub.lineup?.errors || 0 } : {}

  return (
    <AppShell
      header={
        <SeasonHeader
          title={live ? 'Ao vivo' : TITLES[tab]}
          career={hub?.career}
          season={hub?.season}
          remaining={remaining}
          onBack={!hub ? onBack : live || atHome ? null : goHome}
          backLabel={!hub ? 'Voltar ao menu' : 'Voltar ao início da temporada'}
        />
      }
    >
      <div className="sn-screen">
        {toast && (
          <div className={`sn-toast ${toast.kind} ${toast.action ? 'has-action' : ''}`} role="status" key={toast.id}>
            {toast.action ? (
              <button type="button" onClick={() => { setToast(null); toast.action() }}>
                {toast.text} <small>Abrir</small>
              </button>
            ) : (
              toast.text
            )}
          </div>
        )}

        <div className="sn-scroll" key={tab}>
          {loading && !hub && <LoadingState />}
          {error && !hub && <ErrorState message={error} onRetry={() => refresh()} />}

          {ctx && tab === 'home' && <HomeTab ctx={ctx} actions={actions} />}
          {ctx && tab === 'team' && <TeamTab hub={hub} notify={notify} onSaved={() => refresh({ silent: true })} focusPlayerId={teamFocus} />}
          {ctx && tab === 'matches' && <MatchesTab ctx={ctx} onOpenReport={actions.openReport} />}
          {ctx && tab === 'comps' && (
            <CompetitionsTab ctx={ctx} selected={compSel || ctx.nextEvent?.competition || hub?.competitions?.[0]?.id} onSelect={setCompSel} onOpenReport={actions.openReport} />
          )}
          {ctx && tab === 'world' && hub.world && <WorldPanel key={worldArea} initialArea={worldArea} hub={hub} onRefresh={actions.refresh} worldStatus={worldStatus} onHome={() => goTab('home')} />}
          {ctx && tab === 'career' && <CareerTab ctx={ctx} initialView={careerView} actions={actions} />}
        </div>

        {ctx && !live && <BottomNav worldAvailable={!!hub.world} active={tab} onChange={(id) => goTab(id)} badges={badges} />}

        {preMatch && !live && ctx && hub.next_event?.kind === 'mine' && hub.next_event.fixture_id === preMatch && !hub.live_match && (
          <PreMatch
            next={hub.next_event}
            myClub={ctx.myClub}
            myPos={hub.competitions.find((c) => c.id === hub.next_event.competition)?.table?.played ? hub.competitions.find((c) => c.id === hub.next_event.competition).table.pos : null}
            lineupErrors={hub.lineup?.errors ?? 0}
            canPlay={canPlay}
            blockedText={blockedText}
            starting={busy === 'start'}
            engineVersion={hub.simulation_version ?? 1}
            onStart={play}
            onLineup={() => {
              setPreMatch(null)
              goTab('team')
            }}
            onClose={() => setPreMatch(null)}
          />
        )}

        {live && <MatchLive initial={live} myClub={ctx?.myClub} onFinished={onMatchFinished} notify={notify} />}

        {summary && (
          <PostMatch
            summary={summary}
            seasonId={hub?.season.id}
            byComp={byComp}
            onClose={() => {
              setSummary(null)
              setTab('home')
              refresh({ silent: true })
            }}
            onOffers={() => {
              setSummary(null)
              goTab('career', 'offers')
            }}
          />
        )}

        {digest && (
          <ParallelDigest
            digest={digest}
            myClub={ctx?.myClub}
            onOpenReport={actions.openReport}
            onOffers={() => {
              setDigest(null)
              goTab('career', 'offers')
            }}
            onClose={() => {
              setDigest(null)
              setTab('home')
            }}
          />
        )}

        {report && <MatchReport fixtureId={report} onClose={() => setReport(null)} />}
        {inbox && hub && <InboxSheet messages={hub.messages} focusId={inbox.focusId} initialCategory={inbox.category} onSeen={seenInbox} onAction={inboxAction} onClose={() => setInbox(null)} />}


      </div>
    </AppShell>
  )
}
