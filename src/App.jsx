import { useEffect, useState } from 'react'
import { ThemeProvider } from './context/ThemeContext'
import { AuthProvider, useAuth } from './context/AuthContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import ClubOfferScreen from './features/club/ClubOfferScreen'
import HomeScreen from './features/home/HomeScreen'
import { getActiveCareer } from './features/player/playerService'
import './styles/theme.css'

function Gate() {
  const { status, user } = useAuth()
  const [career, setCareer] = useState(null)
  // Enquanto confere no banco se esse usuário já tem carreira — evita
  // mostrar "criar personagem" por um instante pra quem já tem uma.
  const [checkingCareer, setCheckingCareer] = useState(true)

  useEffect(() => {
    if (status !== 'signed-in') {
      // Sem sessão: não há carreira de ninguém pra mostrar.
      setCareer(null)
      setCheckingCareer(false)
      return
    }

    let cancelled = false
    setCheckingCareer(true)
    getActiveCareer(user.id).then((found) => {
      if (cancelled) return
      setCareer(found) // null se essa conta ainda não tem personagem
      setCheckingCareer(false)
    })
    return () => {
      cancelled = true
    }
  }, [status, user?.id])

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

  return <HomeScreen career={career} />
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
