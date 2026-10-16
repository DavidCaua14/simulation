import { useState } from 'react'
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
  // Carreira recém-criada vive aqui enquanto o jogador passa pelas etapas
  // seguintes (escolher clube) — tudo sem reload, trocando de componente.
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
