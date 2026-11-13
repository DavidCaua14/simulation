// Prévia local (somente desenvolvimento) da escalação das Temporadas. Não entra no build do jogo.
import './seasons-mock.js'
import { createRoot } from 'react-dom/client'
import '../../src/styles/theme.css'
import '../../src/styles/game-ui.css'
import '../../src/styles/cm-skin.css'
import '../../src/styles/cm-screens.css'
import '../../src/features/seasons/seasons.css'
import '../../src/features/seasons/manager.css'
import '../../src/features/cards/cards.css'
import TeamTab from '../../src/features/seasons/tabs/TeamTab'

const hub = { coach: { club_id: 'flamengo' }, season: { day_no: 1 }, world: { today: '2026-11-13', roster_revision: 1 } }
createRoot(document.getElementById('root')).render(
  <div style={{ maxWidth: 430, margin: '0 auto', padding: 12 }}><TeamTab hub={hub} notify={(m) => console.log(m)} /></div>,
)
