// Prévia local (somente desenvolvimento) do perfil de um amigo. Não entra no build do jogo.
// As chamadas ao Supabase (friend_profile e sim_competitions) devem ser interceptadas pelo teste/navegador.
import { createRoot } from 'react-dom/client'
import '../../src/styles/game-ui.css'
import '../../src/styles/theme.css'
import '../../src/styles/cm-skin.css'
import '../../src/styles/cm-screens.css'
import '../../src/features/friends/friends.css'
import FriendProfile from '../../src/features/friends/FriendProfile'

createRoot(document.getElementById('root')).render(
  <div style={{ position: 'relative', maxWidth: 430, height: '100vh', margin: '0 auto', display: 'flex', flexDirection: 'column' }}>
    <FriendProfile username="brunomartins" onClose={() => {}} onRemove={() => {}} />
  </div>,
)
