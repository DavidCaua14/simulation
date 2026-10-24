import AppShell from '../../components/layout/AppShell'
import PlayerHeader from '../../components/PlayerHeader'
import { getClubById } from '../club/data/clubs'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import { useProfilePrefs } from '../profile/profileStore'
import useWallet from '../predictions/hooks/useWallet'
import RankingTicker from './components/RankingTicker'
import HeroBanner from './components/HeroBanner'
import ModeCard from './components/ModeCard'
import BottomTabBar from './components/BottomTabBar'
import useInbox from '../cards/hooks/useInbox'
import RewardsStrip from '../cards/components/RewardsStrip'
import DailyRewardsModal from '../cards/components/DailyRewardsModal'
import { GAME_MODES } from './data/gameModes'
import './home-screen.css'
import './home-compact.css'
import '../cards/cards.css'

export default function HomeScreen({ career, onNavigate }) {
  const { player } = career
  const club = getClubById(player.clubId)
  const photo = getProfilePhotoById(player.photoId)
  const [prefs] = useProfilePrefs(career.userId) // foto escolhida no Perfil aparece aqui também
  // Começa com os valores da carreira e se atualiza sozinho (prêmios de palpites, etc.)
  const wallet = useWallet({ coins: player.coins, energy: player.energy, diamonds: player.diamonds })
  // Ao chegar na Home o banco entrega as caixas de boas-vindas (1ª vez) e as diárias (1x por dia).
  const inbox = useInbox({ claim: true })

  return (
    <AppShell header={<PlayerHeader player={player} wallet={wallet} avatarSrc={prefs.avatarUrl || photo?.src} />}>
      <div className="home-shell">
        <RankingTicker />

        <div className="home-scroll">
          <HeroBanner club={club} countryId={player.country} />

          <RewardsStrip count={inbox.count} onSelect={onNavigate} />

          <div className="mode-grid">
            {GAME_MODES.map((mode) => (
              <ModeCard key={mode.id} mode={mode} onSelect={onNavigate} />
            ))}
          </div>
        </div>

        <BottomTabBar active="home" onSelect={onNavigate} />

        {inbox.granted && inbox.boxes.length > 0 && (
          <DailyRewardsModal
            granted={inbox.granted}
            boxes={inbox.boxes}
            onOpened={wallet.refresh}
            onDone={() => {
              inbox.clearGranted()
              inbox.refresh()
              wallet.refresh()
            }}
          />
        )}
      </div>
    </AppShell>
  )
}
