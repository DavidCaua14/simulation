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
import ProfileScreen from './features/profile/ProfileScreen'
import { AudioProvider } from './features/audio/AudioContext'
import { getActiveCareer } from './features/player/playerService'
import './styles/theme.css'

function Gate() {
  const { status, user } = useAuth()
  const [career, setCareer] = useState(null)
  const [checkingCareer, setCheckingCareer] = useState(true)
  // Navegação simples entre as telas do jogo depois do onboarding.
  // 'home' | 'tips' (palpites esportivos) | 'profile'
  const [screen, setScreen] = useState('home')

  // Carrega a carreira do banco sempre que a sessão muda — é isso que faz
  // reload, login de novo e troca de conta caírem na tela certa.
  useEffect(() => {
    if (status === 'signed-out') {
      setCareer(null)
      setScreen('home')
      setCheckingCareer(false)
      return undefined
    }
    if (status !== 'signed-in' || !user) return undefined

    let cancelled = false
    setCheckingCareer(true)
    getActiveCareer(user.id).then((found) => {
      if (cancelled) return
      setCareer(found)
      setCheckingCareer(false)
    })
    return () => {
      cancelled = true
    }
  }, [status, user?.id]) // eslint-disable-line react-hooks/exhaustive-deps

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

  if (!career) {
    return <CreateCharacterScreen userId={user.id} onCreated={setCareer} />
  }

  if (!career.player.clubId) {
    return <ClubOfferScreen career={career} onClubChosen={setCareer} />
  }

  // Só estas telas estão construídas; os demais ids da barra/menu ainda não fazem nada.
  const navigate = (id) => {
    if (id === 'home' || id === 'tips' || id === 'profile' || id === 'seasons') setScreen(id)
  }

  // Nível, XP, moedas e clube mudam no banco enquanto se joga: ao voltar, recarrega a carreira.
  const backHome = () => {
    getActiveCareer(user.id).then((fresh) => fresh && setCareer(fresh))
    setScreen('home')
  }

  if (screen === 'tips') {
    return <PredictionsScreen career={career} onBack={backHome} />
  }

  if (screen === 'seasons') {
    return <SeasonsScreen career={career} onBack={backHome} />
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
          <AudioProvider>
            <Gate />
          </AudioProvider>
        </AuthProvider>
      </ErrorBoundary>
    </ThemeProvider>
  )
}

export default App
