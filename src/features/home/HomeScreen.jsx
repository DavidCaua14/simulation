import AppShell from '../../components/layout/AppShell'
import { getClubById } from '../club/data/clubs'
import PlayerHeader from '../../components/PlayerHeader'
import RankingTicker from './components/RankingTicker'
import HeroBanner from './components/HeroBanner'
import ModeCard from './components/ModeCard'
import BottomTabBar from './components/BottomTabBar'
import { GAME_MODES } from './data/gameModes'
import './home-screen.css'

export default function HomeScreen({ career, onNavigate }) {
  const { player } = career
  const club = getClubById(player.clubId)

  return (
    // AppShell precisa aceitar `header` (ou renderizar sem título/botão à esquerda)
    <AppShell header={<PlayerHeader player={player} />}>
      <div className="home-shell">
        <RankingTicker />

        <div className="home-scroll">
          <HeroBanner club={club} countryId={player.country} />

          <div className="mode-grid">
            {GAME_MODES.map((mode) => (
              <ModeCard key={mode.id} mode={mode} onSelect={onNavigate} />
            ))}
          </div>
        </div>

        <BottomTabBar active="home" onSelect={onNavigate} />
      </div>
    </AppShell>
  )
}
