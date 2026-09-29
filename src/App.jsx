import { ThemeProvider } from './context/ThemeContext'
import { AuthProvider, useAuth } from './context/AuthContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import './styles/theme.css'

function Gate() {
  const { status, user } = useAuth()

  // 'loading': checando se já existe sessão (ex.: acabou de voltar do Google)
  if (status === 'loading') {
    return <AppLoadingScreen label="Entrando em campo..." />
  }

  if (status === 'signed-out') {
    return <LoginScreen />
  }

  return (
    <CreateCharacterScreen
      userId={user.id}
      onCreated={(career) => {
        // Próxima etapa: navegar para a tela inicial (Home) do personagem.
        console.log('Personagem criado:', career)
      }}
    />
  )
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
