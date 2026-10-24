import { useCallback, useEffect, useMemo, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import { getClubById } from '../club/data/clubs'
import useSeasonData from './hooks/useSeasonData'
import useCountdown from './hooks/useCountdown'
import { advanceCalendar, playMatch, respondOffer, startNextSeason } from './services/seasonsApi'
import { flattenFixtures, playerHistory, projectCalendar } from './utils/seasonSelectors'
import { formatRemaining } from './utils/seasonUtils'
import StatusBar from './components/StatusBar'
import BottomNav from './components/BottomNav'
import PostMatch from './components/PostMatch'
import ParallelDigest from './components/ParallelDigest'
import RoundSheet from './components/RoundSheet'
import BoxOpener from '../cards/components/BoxOpener'
import { fetchLatestWinBox } from '../cards/services/cardsApi'
import '../cards/cards.css'
import HomeTab from './tabs/HomeTab'
import MatchesTab from './tabs/MatchesTab'
import CompetitionsTab from './tabs/CompetitionsTab'
import MarketTab from './tabs/MarketTab'
import CareerTab from './tabs/CareerTab'
import './seasons.css'

const TITLES = { home: 'Início', matches: 'Jogos', comps: 'Torneios', market: 'Mercado', career: 'Carreira' }

// Modo Temporadas = "modo carreira" em abas. Os dados são carregados UMA vez (useSeasonData);
// as abas só leem a memória. Só existe uma partida para jogar por vez: a do seu clube.
export default function SeasonsScreen({ onBack }) {
  const { hub, byComp, loading, error, refresh } = useSeasonData()
  const [tab, setTab] = useState('home')
  const [compSel, setCompSel] = useState(null)
  const [playing, setPlaying] = useState(false)
  const [advancing, setAdvancing] = useState(false)
  const [digest, setDigest] = useState(null)
  const [result, setResult] = useState(null)
  const [sheet, setSheet] = useState(null)
  const [busyOffer, setBusyOffer] = useState(null)
  const [starting, setStarting] = useState(false)
  const [toast, setToast] = useState(null)
  const [winBox, setWinBox] = useState(null) // caixa ganha na vitória (aparece no pós-jogo)
  const [openingBox, setOpeningBox] = useState(null)

  const notify = useCallback((text, kind = 'info') => setToast({ text, kind, id: Date.now() }), [])
  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 4200)
    return () => clearTimeout(t)
  }, [toast])

  const remaining = useCountdown(hub?.career.next_reset_at, () => refresh({ silent: true }))

  // ---- dados derivados (tudo em memória) ----------------------------------
  const derived = useMemo(() => {
    if (!hub) return null
    const myClub = hub.career.club_id
    const flat = flattenFixtures(byComp)
    return { myClub, flat, calendar: projectCalendar(byComp, myClub, 14), history: playerHistory(flat), nextEvent: hub.next_event }
  }, [hub, byComp])

  const finished = hub?.season.status === 'finished'
  const hasEnergy = hub ? hub.career.energy + hub.career.bonus_energy > 0 : false
  const canPlay = hasEnergy && !finished && !playing && !advancing
  const blockedText = finished
    ? 'Temporada encerrada'
    : remaining != null
      ? `Sem energia · recarga em ${formatRemaining(remaining)}`
      : 'Sem energia'

  // ---- ações ----------------------------------------------------------------
  async function handlePlay() {
    if (derived?.nextEvent?.kind !== 'mine' || playing) return
    setPlaying(true)
    try {
      const r = await playMatch() // sempre a próxima partida do SEU clube (o calendário é do banco)
      setWinBox(null)
      setResult(r)
      refresh({ silent: true }) // energia, XP, tabelas... atualizam enquanto o placar é revelado
      // Vitória = 1 caixa na caixa de entrada (o banco entrega sozinho); buscamos para mostrar no pós-jogo.
      if (r.result === 'win') fetchLatestWinBox().then(setWinBox).catch(() => {})
    } catch (e) {
      notify(e.message, 'alert')
      refresh({ silent: true })
    } finally {
      setPlaying(false)
    }
  }

  // "Próximo": simula os campeonatos em que seu clube não joga (sem energia) e mostra o resumo
  async function handleAdvance() {
    if (advancing) return
    setAdvancing(true)
    try {
      const d = await advanceCalendar()
      setDigest(d)
      refresh({ silent: true })
    } catch (e) {
      notify(e.message, 'alert')
      refresh({ silent: true })
    } finally {
      setAdvancing(false)
    }
  }

  async function handleOffer(offerId, accept) {
    setBusyOffer(offerId)
    try {
      const r = await respondOffer(offerId, accept)
      await refresh({ silent: true })
      if (r.accepted) {
        notify(`Transferência concluída! Você agora joga pelo ${getClubById(r.club_id)?.name}.`, 'ok')
        setTab('home')
      } else {
        notify('Proposta recusada.', 'info')
      }
    } catch (e) {
      notify(e.message, 'alert')
    } finally {
      setBusyOffer(null)
    }
  }

  async function handleStartNext() {
    setStarting(true)
    try {
      await startNextSeason()
      await refresh({ silent: true })
      setTab('home')
      notify('Nova temporada! Bola rolando.', 'ok')
    } catch (e) {
      notify(e.message, 'alert')
    } finally {
      setStarting(false)
    }
  }

  const closeResult = () => {
    setResult(null)
    setTab('home')
    refresh({ silent: true })
  }

  const openComp = (id) => {
    setCompSel(id)
    setTab('comps')
  }
  const openRound = (f) => setSheet({ comp: f.comp, stage: f.stage, round_no: f.round_no })

  const ctx = hub && derived ? { hub, byComp, ...derived, canPlay, blockedText, playing, advancing, starting } : null

  return (
    <AppShell
      left={
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu">
          <BackIcon />
        </button>
      }
      title={`Temporadas · ${TITLES[tab]}`}
    >
      <div className="sn-screen">
        {toast && <div className={`sn-toast ${toast.kind}`}>{toast.text}</div>}

        {ctx && <StatusBar career={hub.career} season={hub.season} remaining={remaining} />}

        <div className="sn-scroll" key={tab}>
          {loading && !hub && <p className="sn-muted sn-center">Carregando sua temporada…</p>}

          {error && !hub && (
            <div className="sn-empty card">
              <p>{error}</p>
              <button type="button" className="sn-ghost" onClick={() => refresh()}>
                Tentar de novo
              </button>
            </div>
          )}

          {ctx && tab === 'home' && (
            <HomeTab ctx={ctx} onGoTab={setTab} onOpenComp={openComp} onOpenRound={openRound} onPlay={handlePlay} onAdvance={handleAdvance} onStartNext={handleStartNext} />
          )}
          {ctx && tab === 'matches' && <MatchesTab ctx={ctx} onOpenRound={openRound} />}
          {ctx && tab === 'comps' && <CompetitionsTab ctx={ctx} selected={compSel || ctx.nextEvent?.competition || 'brasileirao'} onSelect={setCompSel} />}
          {ctx && tab === 'market' && <MarketTab ctx={ctx} busyId={busyOffer} onRespond={handleOffer} onExpired={() => refresh({ silent: true })} />}
          {ctx && tab === 'career' && <CareerTab ctx={ctx} onRecharged={() => refresh({ silent: true })} />}
        </div>

        {ctx && <BottomNav active={tab} onChange={setTab} badges={{ market: hub.offers.length }} />}

        {sheet && ctx && <RoundSheet target={sheet} byComp={byComp} myClub={ctx.myClub} onClose={() => setSheet(null)} />}

        {digest && (
          <ParallelDigest
            digest={digest}
            myClub={ctx?.myClub}
            onClose={() => {
              setDigest(null)
              setTab('home')
              refresh({ silent: true })
            }}
          />
        )}

        {result && (
          <PostMatch
            result={result}
            byComp={byComp}
            onClose={closeResult}
            box={winBox}
            onOpenBox={() => winBox && setOpeningBox([winBox])}
            onOpenOffers={() => {
              setResult(null)
              setTab('market')
              refresh({ silent: true })
            }}
          />
        )}

        {openingBox && (
          <BoxOpener
            boxes={openingBox}
            onOpened={() => refresh({ silent: true })} /* energia bônus e moedas mudaram */
            onClose={() => {
              setOpeningBox(null)
              setWinBox(null)
              refresh({ silent: true })
            }}
          />
        )}
      </div>
    </AppShell>
  )
}
