import { ThemeProvider } from './context/ThemeContext'
import CreatePlayerWizard from './features/player/CreatePlayerWizard'
import './styles/theme.css'

function App() {
  return (
    <ThemeProvider>
      <CreatePlayerWizard
        onCreated={(career) => {
          // Próxima etapa: navegar para a Home/tela de carreira.
          console.log('Carreira criada:', career)
        }}
      />
    </ThemeProvider>
  )
}

export default App
