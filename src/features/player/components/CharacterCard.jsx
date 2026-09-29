import { UsernameIcon, StarIcon } from '../../../components/ui/icons'
import { CountryFlag } from './flags'
import { getCountryById } from '../data/countries'
import './CharacterCard.css'

export default function CharacterCard({ photo, nickname, countryId, age, level, xp, xpToNext }) {
  const country = getCountryById(countryId)
  const xpPercent = xpToNext > 0 ? Math.min(100, Math.round((xp / xpToNext) * 100)) : 0
  const subtitle = [country?.name, age ? `${age} anos` : null].filter(Boolean).join(' · ')

  return (
    <div className="character-card">
      <div className="portrait-stage">
        <div className="portrait-ring">
          {photo ? (
            <img className="portrait-img" src={photo.src} alt={`Foto de perfil: ${photo.label}`} />
          ) : (
            <div className="portrait-img portrait-empty">
              <UsernameIcon size={32} />
            </div>
          )}
        </div>
        <div className="level-badge">
          <StarIcon />
          <span>NV {level}</span>
        </div>
      </div>

      <div className="nameplate">
        <div className={`nameplate-name ${nickname ? '' : 'is-placeholder'}`}>
          <span>{nickname || 'Novo jogador'}</span>
          {countryId && <CountryFlag countryId={countryId} />}
        </div>
        {subtitle && <div className="nameplate-sub">{subtitle}</div>}
      </div>

      <div className="xp-row" aria-label={`Experiência: ${xp} de ${xpToNext}`}>
        <span>XP</span>
        <div className="xp-bar">
          <div className="xp-fill" style={{ width: `${xpPercent}%` }} />
        </div>
        <span>
          {xp}/{xpToNext}
        </span>
      </div>
    </div>
  )
}
