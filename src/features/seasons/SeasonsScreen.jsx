import { isSessionError } from '../../lib/sessionRecovery'
import { useCallback, useEffect, useMemo, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { getClubById } from '../club/data/clubs'
import useManagerData from './hooks/useManagerData'
import useCountdown from './hooks/useCountdown'
import useWorldSimulation from './hooks/useWorldSimulation'
import WorldPanel from './world/WorldPanel'
import { advanceDays, markMessagesRead, resign, respondOffer, startMatch, startNextSeason } from './services/managerApi'
import { flattenFixtures, playerHistory, projectCalendar } from './utils/seasonSelectors'
import { formatRemaining } from './utils/seasonUtils'
import SeasonHeader from './ui/SeasonHeader'
import { ErrorState, LoadingState } from './ui/States'
import BottomNav from './components/BottomNav'
import PostMatch from './components/PostMatch'
import MatchLive from './components/MatchLive'
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
// a tela envia decisões e acompanha automaticamente as partidas do mundo entre os jogos do treinador.
export default function SeasonsScreen({ onBack }) {
  const { hub, byComp, loading, error, refresh } = useManagerData()
  const [tab, setTab] = useState('home')
  const [careerView, setCareerView] = useState(null)
  const [compSel, setCompSel] = useState(null)
  const [busy, setBusy] = useState(null) // 'start' | 'advance' | 'next' | 'resign' | 'offer:<id>'
  const [live, setLive] = useState(null) // payload da partida ao vivo
  const [summary, setSummary] = useState(null) // pós-jogo
  const [digest, setDigest] = useState(null)
  const [report, setReport] = useState(null)
  const [inbox, setInbox] = useState(null)
  const [toast, setToast] = useState(null)

  const worldStatus = useWorldSimulation({ hub, refresh, paused: !!busy || !!live })

  const notify = useCallback((text, kind = 'info') => setToast({ text, kind, id: Date.now() }), [])
  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 4200)
    return () => clearTimeout(t)
  }, [toast])

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
    setTab(id)
    if (id === 'career') setCareerView(sub)
  }, [])

  // ---- ações ----
  async function run(kind, fn) {
    if (busy || worldStatus === 'syncing') return null
    setBusy(kind)
    try {
      return await fn()
    } catch (e) {
      if (isSessionError(e)) return null
      notify(e.message, 'alert')
      refresh({ silent: true })
      return null
    } finally {
      setBusy(null)
    }
  }

  const play = () =>
    run('start', async () => {
      const p = await startMatch() // idempotente: retoma a partida em andamento sem cobrar energia de novo
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

  const openInbox = (focusId = null) => setInbox({ focusId: typeof focusId === 'number' ? focusId : null })
  const seenInbox = () => {
    if (hub?.unread > 0) markMessagesRead().then(() => refresh({ silent: true })).catch(() => {})
  }

  const actions = {
    refresh: () => refresh({ silent: true }),
    play,
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

  const ctx = hub && derived ? { hub, byComp, ...derived, canPlay, blockedText, busy: busy || (worldStatus === 'syncing' ? 'world' : null), worldStatus } : null
  const badges = hub ? { career: hub.offers.length, home: hub.unread > 0 ? hub.unread : 0, team: hub.lineup?.errors || 0 } : {}

  return (
    <AppShell header={<SeasonHeader title={live ? 'Ao vivo' : TITLES[tab]} career={hub?.career} season={hub?.season} remaining={remaining} onBack={onBack} />}>
      <div className="sn-screen">
        {toast && (
          <div className={`sn-toast ${toast.kind}`} role="status" key={toast.id}>
            {toast.text}
          </div>
        )}

        <div className="sn-scroll" key={tab}>
          {loading && !hub && <LoadingState />}
          {error && !hub && <ErrorState message={error} onRetry={() => refresh()} />}

          {ctx && tab === 'home' && <HomeTab ctx={ctx} actions={actions} />}
          {ctx && tab === 'team' && <TeamTab hub={hub} notify={notify} onSaved={() => refresh({ silent: true })} />}
          {ctx && tab === 'matches' && <MatchesTab ctx={ctx} onOpenReport={actions.openReport} />}
          {ctx && tab === 'comps' && (
            <CompetitionsTab ctx={ctx} selected={compSel || ctx.nextEvent?.competition || hub?.competitions?.[0]?.id} onSelect={setCompSel} onOpenReport={actions.openReport} />
          )}
          {ctx && tab === 'world' && hub.world && <WorldPanel hub={hub} onRefresh={actions.refresh} worldStatus={worldStatus} onHome={() => goTab('home')} />}
          {ctx && tab === 'career' && <CareerTab ctx={ctx} initialView={careerView} actions={actions} />}
        </div>

        {ctx && !live && <BottomNav worldAvailable={!!hub.world} active={tab} onChange={(id) => goTab(id)} badges={badges} />}

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
        {inbox && hub && <InboxSheet messages={hub.messages} focusId={inbox.focusId} onSeen={seenInbox} onClose={() => setInbox(null)} />}


      </div>
    </AppShell>
  )
}
