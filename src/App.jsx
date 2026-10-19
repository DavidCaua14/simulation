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
import { getActiveCareer } from './features/player/playerService'
import './styles/theme.css'

function Gate() {
  const { status, user } = useAuth()
  const [career, setCareer] = useState(null)
  const [checkingCareer, setCheckingCareer] = useState(true)
  // Navegação simples entre as telas do jogo depois do onboarding.
  // 'home' | 'tips' (palpites esportivos)
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

  if (screen === 'tips') {
    return <PredictionsScreen career={career} onBack={() => setScreen('home')} />
  }

  // Só 'tips' está construído; os demais ids ainda não fazem nada.
  return <HomeScreen career={career} onNavigate={(id) => id === 'tips' && setScreen('tips')} />
}

function App() {
  return (
    <ThemeProvider>
      <ErrorBoundary>
        <AuthProvider>
          <Gate />
        </AuthProvider>
      </ErrorBoundary>
    </ThemeProvider>
  )
}

export default App
