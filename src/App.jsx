import { useState } from 'react'
import { ThemeProvider } from './context/ThemeContext'
import AppLoadingScreen from './components/layout/AppLoadingScreen'
import LoginScreen from './features/auth/LoginScreen'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import './styles/theme.css'

// 'login' -> 'entering' (transição sem reload) -> 'character'
const SCREENS = {
  LOGIN: 'login',
  ENTERING: 'entering',
  CHARACTER: 'character',
}

function App() {
  const [screen, setScreen] = useState(SCREENS.LOGIN)

  function handleLogin() {
    // Login ainda não é real — só simula a entrada e segue para a criação
    // do personagem. Quando o Google Sign-In entrar de verdade, troca aqui.
    setScreen(SCREENS.ENTERING)
    setTimeout(() => setScreen(SCREENS.CHARACTER), 900)
  }

  return (
    <ThemeProvider>
      {screen === SCREENS.LOGIN && <LoginScreen onLogin={handleLogin} />}
      {screen === SCREENS.ENTERING && <AppLoadingScreen label="Entrando em campo..." />}
      {screen === SCREENS.CHARACTER && (
        <CreateCharacterScreen
          onCreated={(career) => {
            // Próxima etapa: navegar para a tela inicial (Home) do personagem.
            console.log('Personagem criado:', career)
          }}
        />
      )}
    </ThemeProvider>
  )
}

export default App
