import AvatarBust from './AvatarBust'
import { CountryFlag } from './flags'

export default function PlayerCard({ appearance, nickname, countryId, positionLabel, jerseyNumber }) {
  return (
    <div className="player-card card">
      <div className="player-card-avatar">
        {appearance && <AvatarBust {...appearance} />}
      </div>
      <div className="player-card-info">
        <strong>
          {nickname || 'Seu jogador'}
          {countryId && <CountryFlag countryId={countryId} className="player-card-flag" />}
        </strong>
        <span>
          {positionLabel || 'Posição não definida'}
          {jerseyNumber ? ` · #${jerseyNumber}` : ''}
        </span>
      </div>
    </div>
  )
}
