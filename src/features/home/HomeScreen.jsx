import AppShell from '../../components/layout/AppShell'
import CharacterCard from '../player/components/CharacterCard'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import { getClubById } from '../club/data/clubs'
import { PLACEHOLDER_XP_TO_NEXT_LEVEL } from '../player/data/gameConstants'
import { ShieldIcon, TicketIcon, ChevronRightIcon } from '../../components/ui/icons'
import './home-screen.css'

export default function HomeScreen({ career, onOpenPredictions }) {
  const { player } = career
  const photo = getProfilePhotoById(player.photoId)
  const club = getClubById(player.clubId)

  return (
    <AppShell left={<ShieldIcon />} title="Início">
      <div className="home-body">
        <CharacterCard
          photo={photo}
          nickname={player.nickname}
          countryId={player.country}
          age={player.age}
          level={player.level}
          xp={player.xp}
          xpToNext={PLACEHOLDER_XP_TO_NEXT_LEVEL}
        />

        {club && (
          <div className="home-club card">
            <span className="home-club-shield">
              <img src={club.shield} alt="" />
            </span>
            <div>
              <span className="home-club-label">Clube atual</span>
              <strong>{club.name}</strong>
            </div>
          </div>
        )}

        {onOpenPredictions && (
          <button type="button" className="home-action card" onClick={onOpenPredictions}>
            <span className="home-action-icon">
              <TicketIcon />
            </span>
            <span className="home-action-text">
              <strong>Palpites esportivos</strong>
              <small>Brasileirão A, B e C · ganhe XP, moedas e energia</small>
            </span>
            <ChevronRightIcon />
          </button>
        )}

        <div className="home-placeholder card">
          <p>
            A tela inicial completa (treinos, partidas, elenco e troca de clube) ainda está em
            construção. Por enquanto, isso confirma que seu personagem já está salvo e vinculado
            ao {club?.name ?? 'seu clube'}.
          </p>
        </div>
      </div>
    </AppShell>
  )
}
