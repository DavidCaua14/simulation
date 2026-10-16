import { useEffect, useState } from 'react'
import { ThemeProvider } from './context/ThemeContext'
import { AuthProvider, useAuth } from './context/AuthContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import ClubOfferScreen from './features/club/ClubOfferScreen'
import HomeScreen from './features/home/HomeScreen'
import PredictionsScreen from './features/predictions/PredictionsScreen'
import './styles/theme.css'

function Gate() {
  const { status, user } = useAuth()
  const [career, setCareer] = useState(null)
  // Navegação simples entre as telas do jogo depois do onboarding.
  const [screen, setScreen] = useState('home')

  // 'loading': checando se já existe sessão (ex.: acabou de voltar do Google)
  if (status === 'loading') {
    return <AppLoadingScreen label="Entrando em campo..." />
  }

  if (status === 'signed-out') {
    return <LoginScreen />
  }

  // Carrega a carreira do banco antes de decidir a tela — é isso que faz
  // reload, login de novo e troca de conta sempre caírem no lugar certo.
  if (checkingCareer) {
    return <AppLoadingScreen label="Carregando sua carreira..." />
  }

  if (!career) {
    return <CreateCharacterScreen userId={user.id} onCreated={setCareer} />
  }

  if (!career.player.clubId) {
    return <ClubOfferScreen career={career} onClubChosen={setCareer} />
  }

  if (screen === 'predictions') {
    return <PredictionsScreen career={career} onBack={() => setScreen('home')} />
  }

  return <HomeScreen career={career} onOpenPredictions={() => setScreen('predictions')} />
}

function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <Gate />
      </AuthProvider>
    </ThemeProvider>
  )
}

export default App
