import { Building2, ChevronRight, Megaphone, Star } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { boardMood, fansMood, reputationTier } from '../utils/managerUtils'

export function Stars({ value }) {
  return (
    <span className="rp-stars" aria-label={`${value} de 5 estrelas`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} size={12} className={value >= i ? 'on' : value >= i - 0.5 ? 'half' : ''} fill={value >= i - 0.5 ? 'currentColor' : 'none'} />
      ))}
    </span>
  )
}

export function Meter({ icon: Icon, label, value, mood }) {
  return (
    <span className={`cst-meter t-${mood.tone}`}>
      <span className="cst-meter-head">
        <Icon size={14} /> {label}
        <b>{mood.label}</b>
      </span>
      <i role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={value} aria-label={label}>
        <em style={{ width: `${Math.max(3, value)}%` }} />
      </i>
    </span>
  )
}

// Situação do treinador no clube: diretoria, torcida e reputação. Os dois primeiros decidem se ele fica.
export default function CoachStatusCard({ coach, onOpen }) {
  const rep = reputationTier(coach.reputation)
  const club = coach.club_id ? getClubById(coach.club_id) : null
  const sp = coach.spell
  return (
    <button type="button" className="cst" onClick={onOpen} style={{ '--cc': club?.colors?.[0] || '#2a3550' }}>
      <span className="cst-top">
        {club ? <ClubCrest clubId={club.id} size={40} /> : <span className="cst-nocrest">?</span>}
        <span className="cst-id">
          <small>{club ? 'Seu clube' : 'Situação'}</small>
          <b>{club ? club.name : 'Sem clube'}</b>
          {sp && club && (
            <span className="cst-rec">
              {sp.matches} jogos · <em className="w">{sp.wins}V</em> <em className="d">{sp.draws}E</em> <em className="l">{sp.losses}D</em>
            </span>
          )}
        </span>
        <span className="cst-rep">
          <Stars value={rep.stars} />
          <small>{rep.label}</small>
        </span>
        <ChevronRight size={16} className="cst-chev" />
      </span>
      {club && (
        <span className="cst-meters">
          <Meter icon={Building2} label="Diretoria" value={coach.board} mood={boardMood(coach.board)} />
          <Meter icon={Megaphone} label="Torcida" value={coach.fans} mood={fansMood(coach.fans)} />
        </span>
      )}
    </button>
  )
}
