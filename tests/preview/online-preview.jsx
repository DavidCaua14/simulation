// Prévia local (somente desenvolvimento) do modo online. Não entra no build do jogo.
// online-mock.js responde às chamadas on_* com dados fictícios; nada vai ao Supabase.
import './online-mock.js'
import { createRoot } from 'react-dom/client'
import '../../src/styles/theme.css'
import '../../src/styles/game-ui.css'
import '../../src/styles/desktop.css'
import '../../src/styles/cm-skin.css'
import '../../src/styles/cm-screens.css'
import OnlineScreen from '../../src/features/online/OnlineScreen'
import { AudioProvider } from '../../src/features/audio/AudioContext'

createRoot(document.getElementById('root')).render(
  <AudioProvider>
    <OnlineScreen onBack={() => window.history.back()} />
  </AudioProvider>,
)
