import { isSessionError } from '../../lib/sessionRecovery'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { getClubById } from '../club/data/clubs'
import useManagerData from './hooks/useManagerData'
import useCountdown from './hooks/useCountdown'
import { createWorldSimulation } from './utils/worldSimulation'
import { acknowledgeAttention, advanceWorld, dateLabel, newsFeed, readNews, requestId } from './services/careerWorldApi'
import WorldPanel from './world/WorldPanel'
import TransfersPanel from './transfers/TransfersPanel'
import { advanceDays, fetchHub, markMessagesRead, resign, respondOffer, startMatch, startNextSeason } from './services/managerApi'
import { flattenFixtures, playerHistory, projectCalendar } from './utils/seasonSelectors'
import { msgCategory } from './utils/managerUtils'
import { reportLevel } from '../progress/levelEvents'
import { formatRemaining } from './utils/seasonUtils'
import SeasonHeader from './ui/SeasonHeader'
import { ErrorState, LoadingState } from './ui/States'
import BottomNav from './components/BottomNav'
import CoachAssistant from './components/CoachAssistant'
import { assistantDone, assistantKey } from './utils/assistantStore'
import ClubCentral from './components/ClubCentral'
import PostMatch from './components/PostMatch'
import MatchLive from './components/MatchLive'
import MatchFlow from './matchflow/MatchFlow'
import MatchReport from './components/MatchReport'
import ParallelDigest from './components/ParallelDigest'
import SeasonReward from './components/SeasonReward'
import InboxSheet from './components/InboxSheet'
import '../cards/cards.css'
import HomeTab from './tabs/HomeTab'
import TeamTab from './tabs/TeamTab'
import MatchesTab from './tabs/MatchesTab'
import CompetitionsTab from './tabs/CompetitionsTab'
import CareerTab from './tabs/CareerTab'
import './seasons.css'
import './manager.css'

const TITLES = { home: 'Início', team: 'Time', matches: 'Jogos', comps: 'Torneios', career: 'Carreira', world: 'Finanças', transfers: 'Transferências' }

// MODO CARREIRA (treinador): você comanda um clube real. Tudo é decidido no banco (supabase/manager/*.sql);
// O avanço até a próxima partida processa as competições paralelas no mesmo calendário.
export default function SeasonsScreen({ career: account, onBack }) {
  const [tab, setTab] = useState('home')
  const [compSel, setCompSel] = useState(null)
  const { hub, byComp, loading, error, refresh } = useManagerData(tab, compSel)
  const [careerView, setCareerView] = useState(null)
  const [busy, setBusy] = useState(null) // 'start' | 'advance' | 'next' | 'resign' | 'offer:<id>'
  const [live, setLive] = useState(null) // payload da partida ao vivo
  const [summary, setSummary] = useState(null) // pós-jogo
  const [preMatch, setPreMatch] = useState(null) // próximo jogo aberto no fluxo da partida (Formação → pré-jogo)
  const [digest, setDigest] = useState(null)
  const [report, setReport] = useState(null)
  const [inbox, setInbox] = useState(null)
  const [worldArea, setWorldArea] = useState('news')
  const [teamFocus, setTeamFocus] = useState(null)
  const [teamView, setTeamView] = useState({ view: null, section: null, n: 0 }) // aberto pela Central do clube
  const [central, setCentral] = useState(false)
  const [toast, setToast] = useState(null)
  const [assistant, setAssistant] = useState(() => !assistantDone(account?.id))

  const actionLock = useRef(false)
  const mounted = useRef(true)
  useEffect(() => { mounted.current = true; return () => { mounted.current = false } }, [])
  const simulation = useMemo(() => createWorldSimulation({ advance: advanceWorld, refresh, peek: () => fetchHub(), requestId, storage: window.localStorage }), [refresh])
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

  // Subiu de nível numa partida ou recompensa: animação global de novo nível.
  useEffect(() => {
    if (hub?.career?.level) reportLevel(account?.userId, hub.career.level)
  }, [hub?.career?.level, account?.userId])

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
  // Rodada a rodada: o botão JOGAR fica disponível mesmo antes do dia do jogo — ele resolve a rodada e abre o pré-jogo.
  const canGo = (hasEnergy || Boolean(hub?.live_match)) && !finished && !busy
  // Fluxo da partida: o jogo aberto está pronto quando o calendário do servidor chegou ao dia dele.
  const matchReady = Boolean(preMatch && hub?.next_event?.kind === 'mine' && hub.next_event.fixture_id === preMatch.fixture_id && !(hub.next_event.days_until > 0) && !hub.world?.needs_sync && busy !== 'prepare')
  const blockedText = worldStatus === 'syncing' ? 'Preparando a próxima partida…' : finished ? 'Temporada encerrada' : remaining != null ? `Sem energia · recarga em ${formatRemaining(remaining)}` : 'Sem energia'

  // CM17: o antigo "Mundo" virou Transferências (busca, pré-seleção, negociações, venda); Finanças fica no Clube.
  const goTab = useCallback((target, sub = null) => {
    const id = target === 'world' && sub !== 'finance' ? 'transfers' : target
    setTeamFocus(id === 'team' ? sub : null)
    setCentral(false)
    setTab(id)
    if (id === 'career') setCareerView(sub)
    if (id === 'world') setWorldArea('finance')
    if (id === 'transfers') setWorldArea(sub === 'deals' ? 'deals' : sub === 'shortlist' ? 'shortlist' : 'search')
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

  // JOGAR: resolve o mundo até o dia da sua partida (jogos da IA, mercado, mensagens) e abre o pré-jogo.
  // Decisões urgentes (propostas, prazos) interrompem antes do jogo, como os e-mails do CM.
  // Como no CM17, os dias não aparecem passando: a tela de Formação abre na hora e o mundo é resolvido
  // em segundo plano até o dia do jogo. O Pontapé inicial só libera quando o servidor chega lá.
  const prepareInBackground = (from) =>
    run('prepare', async () => {
      const current = await simulation.prepare(from, { isActive: () => mounted.current })
      if (!current || !mounted.current) return
      if (current.season?.status === 'finished' || current.coach?.status !== 'employed') {
        setPreMatch(null)
        notify(current.season?.status === 'finished' ? 'Temporada encerrada. Veja o balanço no Início.' : 'Sua situação no clube mudou. Veja as mensagens.', 'info')
      }
    })
  const goToMatch = () => {
    const next = hub?.next_event
    if (next?.kind !== 'mine') return
    setPreMatch(next)
    if (hub.world && !hub.attention && (hub.world.needs_sync || next.days_until > 0)) prepareInBackground(hub)
  }
  // E-mail urgente durante o fluxo: "Depois" segue a preparação sem responder (o prazo continua contando).
  const laterAttention = () =>
    run('attention', async () => {
      await acknowledgeAttention(hub.attention.key)
      const h = await refresh({ silent: true })
      if (h && mounted.current) setTimeout(() => prepareInBackground(h), 0)
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
      const d = hub.world ? await advanceWorld(untilOffer ? 14 : 1, requestId(), hub.runtime_version) : await advanceDays(untilOffer)
      setDigest(d)
      refresh({ silent: true })
      if (d.more) notify('Avançamos o máximo possível de uma vez. Toque em avançar de novo para continuar.', 'info')
    })

  const respond = (offerId, accept) =>
    run(`offer:${offerId}`, async () => {
      const r = await respondOffer(offerId, accept)
      await refresh({ silent: true })
      if (r.accepted) {
        const timing = r.off_season ? 'Você assumiu na entressafra. A data do save foi mantida.' : 'A temporada segue de onde parou.'
        notify(`Contrato assinado! Você é o novo treinador: ${getClubById(r.club_id)?.name}. ${timing}`, 'ok')
        setTab('home')
      } else notify('Proposta recusada.', 'info')
    })

  const startNext = () =>
    run('next', async () => {
      if (hub.world) {
        const ready = await simulation.prepare(hub, { isActive: () => mounted.current })
        if (!ready || ready.attention) return
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

  // E-mail (CM17): mensagens do clube + notícias do mundo do futebol numa só caixa de entrada.
  const [worldMail, setWorldMail] = useState([])
  const openInbox = (focus = null) => {
    setInbox({ focusId: typeof focus === 'number' ? focus : null, category: typeof focus === 'string' ? focus : 'all' })
    if (hub?.world)
      newsFeed()
        .then((rows) =>
          mounted.current &&
          setWorldMail((rows || []).map((n) => ({ id: `n${n.id}`, newsId: n.id, kind: 'news', category: 'world', title: n.title, body: n.body, read: n.read, club_id: n.club_id, day_label: dateLabel(n.on_date) }))),
        )
        .catch(() => {})
  }
  const seenInbox = (ids) => {
    const news = (ids || []).filter((id) => typeof id === 'string' && id.startsWith('n')).map((id) => Number(id.slice(1)))
    const msgs = (ids || []).filter((id) => typeof id === 'number')
    if (msgs.length) markMessagesRead(msgs).then(() => refresh({ silent: true })).catch(() => {})
    if (news.length) readNews(news).then(() => setWorldMail((list) => list.map((m) => (news.includes(m.newsId) ? { ...m, read: true } : m)))).catch(() => {})
  }
  // Atalho de cada mensagem: leva à tela onde a decisão é tomada.
  const inboxAction = (m) => {
    setInbox(null)
    if (m.action === 'open_negotiations' || m.action === 'open_finance') {
      setWorldArea(m.action === 'open_finance' ? 'finance' : 'deals')
      setTab(m.action === 'open_finance' ? 'world' : 'transfers')
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
    setCentral(false)
    setTab('home')
  }

  const actions = {
    exit: onBack,
    refresh: () => refresh({ silent: true }),
    play,
    // Dia de jogo: abre o pré-jogo; a partida (e o gasto de energia) só começa em "Iniciar partida"
    openPreMatch: goToMatch,
    goToMatch,
    prepareNext,
    deferAttention: () => run('attention', async () => {
      await acknowledgeAttention(hub.attention.key)
      await refresh({ silent: true })
    }),
    openAttention: () => {
      if (hub.attention?.action === 'offers') goTab('career', 'offers')
      else if (hub.attention?.action === 'contract') goTab('career', 'profile')
      else if (hub.attention?.action === 'contracts') goTab('team')
      else { setWorldArea('deals'); setTab('world') }
    },
    advance,
    startNext,
    goTab,
    goHome,
    openTeam: (view, section = null) => {
      setTeamFocus(null)
      setTeamView((t) => ({ view, section, n: t.n + 1 }))
      setTab('team')
    },
    openCentral: () => setCentral(true),
    restartAssistant: () => {
      try {
        window.localStorage.removeItem(assistantKey(account?.id))
      } catch {
        /* armazenamento indisponível */
      }
      setTab('home')
      setAssistant(true)
    },
    openInbox,
    respondOffer: respond,
    resign: doResign,
    openReport: (f) => setReport(typeof f === 'number' ? f : f.id),
    openComp: (id) => {
      setCompSel(id)
      setTab('comps')
    },
  }

  const ctx = hub && derived ? { hub, byComp, ...derived, canPlay, canGo, blockedText, busy: busy || (worldStatus === 'syncing' ? 'world' : null), worldStatus, prepareProgress } : null
  const badges = hub ? { career: hub.offers.length, home: hub.unread > 0 ? hub.unread : 0, team: hub.lineup?.errors || 0 } : {}

  return (
    <AppShell
      header={
        <SeasonHeader
          title={live ? 'Ao vivo' : TITLES[tab]}
          clubId={hub?.coach?.status === 'employed' ? hub.coach.club_id : null}
          career={hub?.career}
          season={hub?.season}
          remaining={remaining}
          onBack={!hub ? onBack : live || atHome ? null : goHome}
          onMenu={hub && !live ? () => setCentral((c) => !c) : null}
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
          {ctx && tab === 'team' && <TeamTab key={teamView.n} hub={hub} notify={notify} onSaved={() => refresh({ silent: true })} focusPlayerId={teamFocus} initialView={teamView.view} initialSection={teamView.section} actions={actions} />}
          {ctx && tab === 'matches' && <MatchesTab ctx={ctx} actions={actions} />}
          {ctx && tab === 'comps' && (
            <CompetitionsTab ctx={ctx} selected={compSel || ctx.nextEvent?.competition || hub?.competitions?.[0]?.id} onSelect={setCompSel} onOpenReport={actions.openReport} />
          )}
          {ctx && tab === 'transfers' && hub.world && <TransfersPanel key={worldArea} initialArea={worldArea} hub={hub} notify={notify} onRefresh={actions.refresh} onTeam={(playerId) => goTab('team', playerId)} />}
          {ctx && tab === 'world' && hub.world && <WorldPanel key={worldArea} initialArea="finance" financeOnly hub={hub} onRefresh={actions.refresh} worldStatus={worldStatus} onHome={() => goTab('home')} onTeam={playerId => goTab('team', playerId)} />}
          {ctx && tab === 'career' && <CareerTab key={careerView || 'profile'} ctx={ctx} initialView={careerView} actions={actions} />}
        </div>

        {ctx && !live && <BottomNav worldAvailable={!!hub.world} active={tab} onChange={(id) => goTab(id)} badges={badges} />}

        {ctx && assistant && !live && !preMatch && !summary && hub.coach?.status === 'employed' && (
          <CoachAssistant careerId={account?.id} onTab={(id) => (id !== 'world' || hub.world) && goTab(id)} onClose={() => setAssistant(false)} />
        )}

        {preMatch && !live && ctx && !hub.live_match && (
          <MatchFlow
            hub={hub}
            next={hub.next_event?.kind === 'mine' && hub.next_event.fixture_id === preMatch.fixture_id ? hub.next_event : preMatch}
            myClub={ctx.myClub}
            myPos={hub.competitions.find((c) => c.id === preMatch.competition)?.table?.played ? hub.competitions.find((c) => c.id === preMatch.competition).table.pos : null}
            ready={matchReady}
            waitingText={busy === 'prepare' ? 'Preparando a partida…' : hub.attention ? 'Veja o e-mail' : 'Aguarde…'}
            attention={Boolean(hub.attention) && busy !== 'prepare'}
            canPlay={(hasEnergy || Boolean(hub.live_match)) && !finished}
            blockedText={blockedText}
            starting={busy === 'start'}
            notify={notify}
            onAttention={() => {
              setPreMatch(null)
              actions.openAttention()
            }}
            onLater={laterAttention}
            onSaved={() => refresh({ silent: true })}
            onStart={play}
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
        {hub?.season_reward && !live && !preMatch && !digest && !report && (
          <SeasonReward reward={hub.season_reward} onClose={() => refresh({ silent: true })} />
        )}
        {central && ctx && !live &&<ClubCentral hub={hub} actions={actions} onClose={() => setCentral(false)} />}
        {inbox && hub && <InboxSheet messages={[...hub.messages, ...worldMail]} focusId={inbox.focusId} initialCategory={inbox.category} onSeen={seenInbox} onAction={inboxAction} onClose={() => setInbox(null)} />}


      </div>
    </AppShell>
  )
}
