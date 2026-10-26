import AppShell from '../../components/layout/AppShell'
import PlayerHeader from '../../components/PlayerHeader'
import { getClubById } from '../club/data/clubs'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import { useProfilePrefs } from '../profile/profileStore'
import useWallet from '../predictions/hooks/useWallet'
import useInbox from '../cards/hooks/useInbox'
import DailyRewardsModal from '../cards/components/DailyRewardsModal'
import RankingTicker from './components/RankingTicker'
import MatchdayHero from './components/MatchdayHero'
import PlayModeCard from './components/PlayModeCard'
import CardsHub from './components/CardsHub'
import QuickTile from './components/QuickTile'
import useEventsBadge from '../events/useEventsBadge'
import BottomTabBar from './components/BottomTabBar'
import useCollectionSummary from './hooks/useCollectionSummary'
import { GAME_MODES } from './data/gameModes'
import './home.css'
import '../cards/cards.css'

const modeById = (id) => GAME_MODES.find((m) => m.id === id)
const QUICK = ['ranking', 'events', 'messages', 'friends']

// Tela inicial, em ordem de importância:
//   1. topo (HUD): atleta, nível/XP e moedas/energia/diamantes
//   2. banner do clube com o botão JOGAR (Temporadas)
//   3. ranking ao vivo com a sua posição
//   4. modos de jogo (palpites, partida online)
//   5. coleção & loja (caixas, vitrine de cartas, loja)
//   6. atalhos secundários (ranking, eventos, mensagens, convites)
export default function HomeScreen({ career, onNavigate }) {
  const { player } = career
  const club = getClubById(player.clubId)
  const photo = getProfilePhotoById(player.photoId)
  const [prefs] = useProfilePrefs(career.userId) // foto escolhida no Perfil aparece aqui também
  // Começa com os valores da carreira e se atualiza sozinho (prêmios de palpites, etc.)
  const wallet = useWallet({ coins: player.coins, energy: player.energy, diamonds: player.diamonds })
  // Ao chegar na Home o banco entrega as caixas de boas-vindas (1ª vez) e as diárias (1x por dia).
  const inbox = useInbox({ claim: true })
  const collection = useCollectionSummary()
  const eventsBadge = useEventsBadge() // recompensas de evento/sequência prontas para resgatar

  const seasons = modeById('seasons')
  const tips = modeById('tips')
  const online = modeById('online-match')
  const store = modeById('store')

  return (
    <AppShell header={<PlayerHeader player={player} wallet={wallet} avatarSrc={prefs.avatarUrl || photo?.src} />}>
      <div className="hm-shell">
        <div className="hm-scroll">
          <MatchdayHero club={club} player={player} onPlay={() => !seasons?.locked && onNavigate?.('seasons')} />

          <RankingTicker me={player.nickname} onOpen={() => onNavigate?.('tips')} />

          <section className="hm-section">
            <h2 className="gx-title">Modos de jogo</h2>
            <div className="hm-modes">
              {tips && <PlayModeCard mode={tips} onSelect={onNavigate} />}
              {online && <PlayModeCard mode={online} onSelect={onNavigate} />}
            </div>
          </section>

          <section className="hm-section">
            <h2 className="gx-title">
              Coleção &amp; loja <small>cartas, caixas e itens</small>
            </h2>
            <CardsHub boxes={inbox.boxes} summary={collection} onNavigate={onNavigate} storeLocked={store?.locked !== false} />
          </section>

          <section className="hm-section">
            <h2 className="gx-title">Mais</h2>
            <div className="hm-quick-grid">
              {QUICK.map((id) => modeById(id)).filter(Boolean).map((m) => (
                <QuickTile key={m.id} mode={m} onSelect={onNavigate} badge={m.id === 'events' ? eventsBadge : 0} />
              ))}
            </div>
          </section>
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
              collection.reload()
            }}
          />
        )}
      </div>
    </AppShell>
  )
}
