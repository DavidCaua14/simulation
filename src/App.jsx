import { Suspense, lazy, useEffect, useState } from 'react'
import { ThemeProvider } from './context/ThemeContext'
import { AuthProvider, useAuth } from './context/AuthContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import ErrorBoundary from './components/ErrorBoundary'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import ClubOfferScreen from './features/club/ClubOfferScreen'
import HomeScreen from './features/home/HomeScreen'
const PredictionsScreen = lazy(() => import('./features/predictions/PredictionsScreen')) // carregada sob demanda
const SeasonsScreen = lazy(() => import('./features/seasons/SeasonsScreen')) // carregada sob demanda
const ProfileScreen = lazy(() => import('./features/profile/ProfileScreen')) // carregada sob demanda
const StoreScreen = lazy(() => import('./features/store/StoreScreen')) // carregada sob demanda
const FriendsScreen = lazy(() => import('./features/friends/FriendsScreen')) // carregada sob demanda
const EventsScreen = lazy(() => import('./features/events/EventsScreen')) // carregada sob demanda
import { AudioProvider, useAudio } from './features/audio/AudioContext'
import { getActiveCareer } from './features/player/playerService'
import LevelUpOverlay from './features/progress/LevelUpOverlay'
import { rememberLevel, reportLevel } from './features/progress/levelEvents'
import UpdateWelcome from './features/update/UpdateWelcome'
const AdminDashboard = lazy(() => import('./features/admin/AdminDashboard')) // carregada sob demanda
const InboxScreen = lazy(() => import('./features/inbox/InboxScreen')) // carregada sob demanda
const RankingScreen = lazy(() => import('./features/ranking/RankingScreen')) // carregada sob demanda
const OnlineScreen = lazy(() => import('./features/online/OnlineScreen')) // carregada sob demanda
const OnlineKickoffAlerts = lazy(() => import('./features/online/OnlineKickoffAlerts')) // só para quem tem acesso ao modo online
import MaintenanceGate from './features/maintenance/MaintenanceGate'
import { isMaintenanceAdmin as isOwner } from './features/maintenance/policy'
import { COMPETITIONS_NEWS_RELEASE, EVENTS_NEWS_RELEASE, MORALE_NEWS_RELEASE, claimReleaseGift, fetchNewsStatus, markNewsSeen, markReleaseSeen } from './features/update/updateApi'
import EventsNews from './features/update/EventsNews'
import CompetitionsNews from './features/update/CompetitionsNews'
import MoraleNews from './features/update/MoraleNews'

// Telas de novidades, da mais nova para a mais antiga. Cada uma aparece uma vez por carreira (release_news).
const NEWS = [
  { id: MORALE_NEWS_RELEASE, Screen: MoraleNews, target: 'seasons' },
  { id: COMPETITIONS_NEWS_RELEASE, Screen: CompetitionsNews, target: 'seasons' },
  { id: EVENTS_NEWS_RELEASE, Screen: EventsNews, target: 'events' },
]
import './styles/theme.css'
import './styles/desktop.css' // por último: tema de jogo, sem barras de rolagem e layout de computador
import './styles/cm-skin.css' // pele CM (Championship Manager 17) para todas as telas
import './styles/cm-screens.css' // telas no formato CM17 (títulos, táticas, torneios, carreira, mundo)

function Gate() {
  const { status, user } = useAuth()
  const { playSfx } = useAudio()
  const [career, setCareer] = useState(null)
  const [checkingCareer, setCheckingCareer] = useState(true)
  const [careerUserId, setCareerUserId] = useState(null)
  const [careerError, setCareerError] = useState(false)
  const [careerAttempt, setCareerAttempt] = useState(0)
  // Navegação simples entre as telas do jogo depois do onboarding.
  // 'home' | 'tips' (palpites esportivos) | 'profile'
  const [screen, setScreen] = useState('home')
  const [screenParams, setScreenParams] = useState(null) // ex.: { tab: 'inbox' } ao abrir as cartas
  const [news, setNews] = useState(null) // novidades: { unseen: [ids], open: id | null, replay }
  const [gift, setGift] = useState(null) // presente da atualização (só quem já jogava): { ...release_gift_claim, open }

  // Carrega a carreira do banco sempre que a sessão muda — é isso que faz
  // reload, login de novo e troca de conta caírem na tela certa.
  useEffect(() => {
    if (status === 'signed-out') {
      setCareer(null)
      setCareerUserId(null)
      setScreen('home')
      setCheckingCareer(false)
      return undefined
    }
    if (status !== 'signed-in' || !user) return undefined

    let cancelled = false
    setCheckingCareer(true)
    setCareerError(false)
    getActiveCareer(user.id).then((found) => {
      if (cancelled) return
      setCareer(found)
      setCareerUserId(user.id)
      setCheckingCareer(false)
    }).catch((e) => {
      if (cancelled) return
      setCareerError([e?.code, e?.message].filter(Boolean).join(' · ') || 'erro desconhecido')
      setCheckingCareer(false)
    })
    return () => {
      cancelled = true
    }
  }, [status, user?.id, careerAttempt]) // eslint-disable-line react-hooks/exhaustive-deps

  const ready = Boolean(career?.player?.clubId) && careerUserId === user?.id
  // Nível mudou em qualquer lugar (partida, evento, presente): animação de novo nível.
  useEffect(() => {
    if (ready) reportLevel(user.id, career.player.level)
  }, [ready, user?.id, career?.player?.level])

  // Presente da atualização: o banco só entrega a quem já jogava antes dela, e uma única vez.
  useEffect(() => {
    if (!ready) return undefined
    let cancelled = false
    claimReleaseGift()
      .then(async (g) => {
        if (cancelled || !g?.eligible) return
        if (g.show) {
          const fresh = await getActiveCareer(user.id).catch(() => null)
          if (cancelled) return
          if (fresh) {
            rememberLevel(user.id, fresh.player.level) // a tela de novidades já anima a subida
            setCareer(fresh)
          }
        }
        setGift({ ...g, open: g.show })
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [ready, user?.id])

  // Novidades: cada tela uma vez por carreira (o banco guarda quem já viu); as não vistas abrem em fila.
  useEffect(() => {
    if (!ready) return undefined
    let cancelled = false
    Promise.all(NEWS.map((n) => fetchNewsStatus(n.id).catch(() => null)))
      .then((list) => {
        if (cancelled) return
        const unseen = NEWS.filter((n, i) => list[i]?.show).map((n) => n.id)
        setNews({ unseen, open: unseen[0] || null, replay: false })
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [ready, user?.id])

  // Painel administrativo: só o dono do jogo (o servidor confere de novo). Abre por /#admin ou pelo Perfil.
  const owner = isOwner(user)
  useEffect(() => {
    if (!owner) return undefined
    const sync = () => {
      if (window.location.hash === '#admin') setScreen('admin')
    }
    sync()
    window.addEventListener('hashchange', sync)
    return () => window.removeEventListener('hashchange', sync)
  }, [owner])

  const closeGift = () => {
    if (gift?.show) markReleaseSeen().catch(() => {})
    setGift((g) => (g ? { ...g, show: false, open: false } : g))
  }
  const giftLayer = gift?.open ? <UpdateWelcome gift={gift} replay={!gift.show} onClose={closeGift} /> : null
  // fecha a novidade aberta (marcando como vista) e abre a próxima não vista, se houver
  const closeNews = () => {
    if (news?.open && !news.replay) markNewsSeen(news.open).catch(() => {})
    setNews((n) => {
      if (!n) return n
      const unseen = n.replay ? n.unseen : n.unseen.filter((id) => id !== n.open)
      return { unseen, open: n.replay ? null : unseen[0] || null, replay: false }
    })
  }
  const goFromNews = (target) => {
    closeNews()
    setScreen(target)
  }
  // o presente antigo (se ainda não visto) vem primeiro; as novidades logo depois
  const newsItem = !gift?.open && news?.open ? NEWS.find((n) => n.id === news.open) : null
  const newsLayer = newsItem
    ? <newsItem.Screen replay={news.replay} onClose={closeNews} onOpenEvents={() => goFromNews(newsItem.target)} onOpenSeasons={() => goFromNews(newsItem.target)} />
    : null

  // 'loading': checando se já existe sessão (ex.: acabou de voltar do Google)
  if (status === 'loading') {
    return <AppLoadingScreen label="Entrando em campo..." />
  }

  if (status === 'signed-out') {
    return <LoginScreen />
  }

  if (checkingCareer) {
    return <AppLoadingScreen label="Carregando sua carreira..." />
  }

  if (careerError) {
    return (
      <main className="app-error" role="alert">
        <h2>Não foi possível carregar sua carreira</h2>
        <p>Tente novamente para continuar de onde parou.</p>
        <small className="app-error-detail">Detalhe: {careerError}</small>
        <button type="button" className="btn-primary" onClick={() => setCareerAttempt((attempt) => attempt + 1)}>
          Tentar novamente
        </button>
      </main>
    )
  }

  if (careerUserId !== user?.id) {
    return <AppLoadingScreen label="Carregando sua carreira..." />
  }

  if (!career) {
    return <CreateCharacterScreen userId={user.id} onCreated={setCareer} />
  }

  if (!career.player.clubId && !career.worldStarted) {
    return <ClubOfferScreen career={career} onClubChosen={setCareer} />
  }

  // Só estas telas estão construídas; os demais ids da barra/menu ainda não fazem nada.
  const navigate = (id, params = null) => {
    if (id === 'messages') id = 'inbox'
    if (id === 'online-match') id = 'online'
    if (id === 'online' && !owner) return // modo online em teste: só o dono do jogo
    if (id === 'home' || id === 'tips' || id === 'profile' || id === 'seasons' || id === 'store' || id === 'friends' || id === 'events' || id === 'inbox' || id === 'ranking' || id === 'online') {
      setScreenParams(params)
      setScreen(id)
      if (id !== 'home') playSfx('open') // abrir telas relevantes (som curto e discreto)
    }
  }

  // Nível, XP, moedas e clube mudam no banco enquanto se joga: ao voltar, recarrega a carreira.
  const openAdmin = owner ? () => {
    window.location.hash = 'admin'
    setScreen('admin')
  } : null
  const backHome = () => {
    if (window.location.hash === '#admin') history.replaceState(null, '', window.location.pathname + window.location.search)
    // Falha passageira ao recarregar não derruba o jogo: mantém a carreira já carregada.
    getActiveCareer(user.id).then((fresh) => fresh && setCareer(fresh)).catch(() => {})
    setScreen('home')
  }

  const openNews = news ? () => setNews((n) => ({ ...n, open: NEWS[0].id, replay: !n.unseen.includes(NEWS[0].id) })) : gift?.eligible ? () => setGift((g) => ({ ...g, open: true })) : null
  const view = renderScreen()
  return (
    <>
      <Suspense fallback={<AppLoadingScreen label="Carregando..." />}>{view}</Suspense>
      {giftLayer}
      {newsLayer}
      {owner && (
        <Suspense fallback={null}>
          <OnlineKickoffAlerts onOpen={(id) => navigate('online', { match: id })} />
        </Suspense>
      )}
    </>
  )

  function renderScreen() {
  if (screen === 'admin' && owner) {
    return <AdminDashboard onBack={backHome} />
  }

  if (screen === 'ranking') {
    return <RankingScreen onBack={backHome} />
  }

  if (screen === 'online' && owner) {
    return <OnlineScreen key={screenParams?.match ?? 'online'} params={screenParams} onBack={backHome} />
  }

  if (screen === 'inbox') {
    return <InboxScreen onBack={backHome} />
  }

  if (screen === 'tips') {
    return <PredictionsScreen career={career} onBack={backHome} />
  }

  if (screen === 'seasons') {
    return <SeasonsScreen career={career} onBack={backHome} />
  }

  if (screen === 'friends') {
    return <FriendsScreen onBack={backHome} />
  }

  if (screen === 'events') {
    return <EventsScreen career={career} onBack={backHome} onNavigate={navigate} />
  }

  if (screen === 'store') {
    return <StoreScreen key={JSON.stringify(screenParams)} career={career} params={screenParams} onBack={backHome} onNavigate={navigate} />
  }

  if (screen === 'profile') {
    return <ProfileScreen career={career} onNavigate={navigate} onOpenNews={openNews} onOpenAdmin={openAdmin} />
  }

  return <HomeScreen career={career} onNavigate={navigate} />
  }
}

function App() {
  return (
    <ThemeProvider>
      <ErrorBoundary>
        <AuthProvider>
          {/* Acima do Gate: a música não para em telas de loading nem em trocas de tela */}
          {/* Manutenção: para desativar, publique enabled: false em public/maintenance.json (ver supabase/maintenance/README.md) */}
          <MaintenanceGate>
            <AudioProvider>
              <Gate />
              <LevelUpOverlay />
            </AudioProvider>
          </MaintenanceGate>
        </AuthProvider>
      </ErrorBoundary>
    </ThemeProvider>
  )
}

export default App
