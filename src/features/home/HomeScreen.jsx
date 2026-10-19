import AppShell from '../../components/layout/AppShell'
import PlayerHeader from '../../components/PlayerHeader'
import { getClubById } from '../club/data/clubs'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import useWallet from '../predictions/hooks/useWallet'
import RankingTicker from './components/RankingTicker'
import HeroBanner from './components/HeroBanner'
import ModeCard from './components/ModeCard'
import BottomTabBar from './components/BottomTabBar'
import { GAME_MODES } from './data/gameModes'
import './home-screen.css'
import './home-compact.css'

export default function HomeScreen({ career, onNavigate }) {
  const { player } = career
  const club = getClubById(player.clubId)
  const photo = getProfilePhotoById(player.photoId)
  // Começa com os valores da carreira e se atualiza sozinho (prêmios de palpites, etc.)
  const wallet = useWallet({ coins: player.coins, energy: player.energy })

  return (
    <AppShell header={<PlayerHeader player={player} wallet={wallet} avatarSrc={photo?.src} />}>
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
