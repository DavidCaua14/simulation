import { getClubById } from '../data/clubs'

// Nome do clube que nunca quebra no meio da palavra: com pouco espaço vira a sigla (FLA, PAL...).
export default function ClubName({ clubId, className = '' }) {
  const club = getClubById(clubId)
  const name = club?.name || clubId || ''
  const short = club?.short || name.slice(0, 3).toUpperCase()
  const size = name.length > 14 ? 'xl' : name.length > 8 ? 'l' : 's'
  return (
    <b className={`club-name ${className}`} data-size={size} title={name}>
      <span className="cn-full">{name}</span>
      <span className="cn-short" aria-hidden="true">{short}</span>
    </b>
  )
}
