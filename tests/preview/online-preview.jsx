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
import OnlineKickoffAlerts from '../../src/features/online/OnlineKickoffAlerts'
import TrainEnergyTab from '../../src/features/store/components/TrainEnergyTab'
import ItemsTab from '../../src/features/store/components/ItemsTab'
import '../../src/features/cards/cards.css'
import '../../src/features/store/store.css'

// ?store=1 mostra só a aba Treino da Loja (energia de treino)
const storeOnly = new URLSearchParams(window.location.search).has('store')
const itemsOnly = new URLSearchParams(window.location.search).has('items')
import { AudioProvider } from '../../src/features/audio/AudioContext'

createRoot(document.getElementById('root')).render(
  <AudioProvider>
    {itemsOnly ? (
      <div style={{ maxWidth: 430, margin: '0 auto', padding: 14 }}><ItemsTab /></div>
    ) : storeOnly ? (
      <div style={{ maxWidth: 430, margin: '0 auto', padding: 14 }}><TrainEnergyTab /></div>
    ) : (
      <>
        <OnlineScreen onBack={() => window.history.back()} />
        <OnlineKickoffAlerts onOpen={(id) => console.log('abrir partida', id)} />
      </>
    )}
  </AudioProvider>,
)
