import { useEffect, useState } from 'react'
import { ThemeProvider } from './context/ThemeContext'
import { AuthProvider, useAuth } from './context/AuthContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import ErrorBoundary from './components/ErrorBoundary'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import ClubOfferScreen from './features/club/ClubOfferScreen'
import HomeScreen from './features/home/HomeScreen'
import PredictionsScreen from './features/predictions/PredictionsScreen'
import SeasonsScreen from './features/seasons/SeasonsScreen'
import CardsScreen from './features/cards/CardsScreen'
import ProfileScreen from './features/profile/ProfileScreen'
import StoreScreen from './features/store/StoreScreen'
import FriendsScreen from './features/friends/FriendsScreen'
import EventsScreen from './features/events/EventsScreen'
import { AudioProvider, useAudio } from './features/audio/AudioContext'
import { getActiveCareer } from './features/player/playerService'
import MaintenanceGate from './features/maintenance/MaintenanceGate'
import './styles/theme.css'

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
    }).catch(() => {
      if (cancelled) return
      setCareerError(true)
      setCheckingCareer(false)
    })
    return () => {
      cancelled = true
    }
  }, [status, user?.id, careerAttempt]) // eslint-disable-line react-hooks/exhaustive-deps

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

  if (!career.player.clubId) {
    return <ClubOfferScreen career={career} onClubChosen={setCareer} />
  }

  // Só estas telas estão construídas; os demais ids da barra/menu ainda não fazem nada.
  const navigate = (id, params = null) => {
    if (id === 'home' || id === 'tips' || id === 'profile' || id === 'seasons' || id === 'cards' || id === 'store' || id === 'friends' || id === 'events') {
      setScreenParams(params)
      setScreen(id)
      if (id !== 'home') playSfx('open') // abrir telas relevantes (som curto e discreto)
    }
  }

  // Nível, XP, moedas e clube mudam no banco enquanto se joga: ao voltar, recarrega a carreira.
  const backHome = () => {
    getActiveCareer(user.id).then((fresh) => fresh && setCareer(fresh)).catch(() => setCareerError(true))
    setScreen('home')
  }

  if (screen === 'tips') {
    return <PredictionsScreen career={career} onBack={backHome} />
  }

  if (screen === 'seasons') {
    return <SeasonsScreen career={career} onBack={backHome} />
  }

  if (screen === 'cards') {
    return <CardsScreen career={career} params={screenParams} onBack={backHome} onNavigate={navigate} />
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
    return <ProfileScreen career={career} onNavigate={navigate} />
  }

  return <HomeScreen career={career} onNavigate={navigate} />
}

function App() {
  return (
    <ThemeProvider>
      <ErrorBoundary>
        <AuthProvider>
          {/* Acima do Gate: a música não para em telas de loading nem em trocas de tela */}
          <MaintenanceGate>
            <AudioProvider>
              <Gate />
            </AudioProvider>
          </MaintenanceGate>
        </AuthProvider>
      </ErrorBoundary>
    </ThemeProvider>
  )
}

export default App
