import AppShell from '../../components/layout/AppShell'
import SignOutButton from '../../components/ui/SignOutButton'
import { getClubById } from '../club/data/clubs'
import RankingTicker from './components/RankingTicker'
import CurrencyRow from './components/CurrencyRow'
import HeroBanner from './components/HeroBanner'
import ModeCard from './components/ModeCard'
import BottomTabBar from './components/BottomTabBar'
import { GAME_MODES } from './data/gameModes'
import './home-screen.css'

// `onNavigate(destino)` é fornecido pelo App.jsx. Os ids dos modos/abas
// ('tips', 'store', ...) são os mesmos usados em gameModes.js e tabs.js.
export default function HomeScreen({ career, onNavigate }) {
  const { player } = career
  const club = getClubById(player.clubId)

  return (
    <AppShell left={<SignOutButton />} title="Início">
      <div className="home-shell">
        <RankingTicker />

        <div className="home-scroll">
          <div className="home-top">
            <CurrencyRow />
            <HeroBanner club={club} countryId={player.country} />
          </div>

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
