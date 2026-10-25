import './identity.css'
import { CountryFlag } from '../../player/components/flags'
import { getCountryById } from '../../player/data/countries'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { PLACEHOLDER_XP_TO_NEXT_LEVEL } from '../../player/data/gameConstants'
import ProfileAvatar from './ProfileAvatar'
import CosmeticIcon from './CosmeticIcon'

const DEFAULT_BG = 'linear-gradient(135deg,#0b4a2a 0%,#1f9d55 100%)'

// Cabeçalho de identidade (o mesmo para o meu perfil, para o perfil de um amigo e para a prévia da loja).
// `preview` sobrepõe itens equipados (ex.: ver como fica uma moldura antes de comprar).
export default function ProfileHero({ profile, preview = {}, actions = null, compact = false }) {
  const eq = { ...(profile?.equipped || {}), ...preview }
  const bg = eq.background?.style
  const theme = eq.theme?.style
  const club = profile?.club_id ? getClubById(profile.club_id) : null
  const country = getCountryById(profile?.country)
  const xp = profile?.xp ?? 0
  const pct = Math.max(0, Math.min(100, (xp / PLACEHOLDER_XP_TO_NEXT_LEVEL) * 100))
  const style = {
    '--pf-accent': theme?.accent || 'var(--primary)',
    '--pf-accent2': theme?.accent2 || 'var(--gold)',
  }
  return (
    <section className={`ph ${compact ? 'is-compact' : ''} ${eq.effect?.style?.type === 'rain' ? 'fx-rain' : ''}`} style={style} aria-label={`Perfil de ${profile?.nickname || ''}`}>
      <div className="ph-bg" style={{ backgroundImage: bg?.css || DEFAULT_BG, backgroundSize: bg?.size || 'cover' }} aria-hidden="true" />
      {eq.effect?.style?.type === 'rain' && <div className="ph-rain" style={{ '--fx-color': eq.effect.style.color }} aria-hidden="true" />}
      {actions && <div className="ph-actions">{actions}</div>}
      <div className="ph-body">
        <ProfileAvatar profile={profile} frame={eq.frame} effect={eq.effect} size={compact ? 76 : 108} xpPct={pct} />
        <h2 className="ph-name">
          {profile?.nickname}
          {eq.emblem && (
            <span className="ph-emblem" style={{ color: eq.emblem.style?.color }} title={eq.emblem.label}>
              <CosmeticIcon name={eq.emblem.style?.icon} size={compact ? 16 : 20} />
            </span>
          )}
        </h2>
        <p className="ph-sub">
          {country && <><CountryFlag countryId={country.id} /> {country.name}</>}
          {club && <> · <ClubCrest clubId={club.id} size={16} /> {club.name}</>}
        </p>
        <div className="ph-level">
          <b>NV {profile?.level ?? 1}</b>
          <span className="ph-xp" aria-label={`XP ${xp} de ${PLACEHOLDER_XP_TO_NEXT_LEVEL}`}><i style={{ width: `${pct}%` }} /></span>
          <small>{xp.toLocaleString('pt-BR')} XP</small>
        </div>
        {!compact && profile?.joined_at && (
          <p className="ph-joined">No jogo desde {new Date(profile.joined_at).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })}</p>
        )}
      </div>
    </section>
  )
}
