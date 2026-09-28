import { ThemeProvider } from './context/ThemeContext'
import CreateCharacterScreen from './features/player/CreateCharacterScreen'
import './styles/theme.css'

function App() {
  return (
    <ThemeProvider>
      <CreateCharacterScreen
        onCreated={(career) => {
          // Próxima etapa: navegar para a tela inicial (Home) do personagem.
          console.log('Personagem criado:', career)
        }}
      />
    </ThemeProvider>
  )
}

export default App
