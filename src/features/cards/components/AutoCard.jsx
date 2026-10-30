import { useId } from 'react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'

const TIER_LABEL = { basica: 'Base' }

function hash(s = '') {
  let h = 0
  for (let i = 0; i < s.length; i += 1) h = (h * 31 + s.charCodeAt(i)) | 0
  return Math.abs(h)
}

// Atleta ilustrado (não é foto): silhueta com a camisa nas cores do clube e o número.
// Variações determinísticas (cabelo/gola) por jogador, para as cartas não ficarem idênticas.
function Avatar({ card, c1, c2 }) {
  const gradientId = `shirt-${useId().replace(/:/g, '')}`
  const h = hash(card.player_key || card.id)
  const hair = h % 4
  const collar = (h >> 3) % 3
  const num = card.meta?.number ?? ((h % 30) + 1)
  return (
    <svg className="ac-avatar" viewBox="0 0 120 120" aria-hidden="true">
      <defs>
        <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor={c1} />
          <stop offset="1" stopColor={c1} stopOpacity="0.75" />
        </linearGradient>
      </defs>
      {/* tronco com a camisa */}
      <path d="M14 120 C16 92 30 80 46 76 L60 84 L74 76 C90 80 104 92 106 120 Z" fill={`url(#${gradientId})`} />
      <path d="M46 76 L60 84 L74 76 L70 72 L60 78 L50 72 Z" fill={c2} />
      {collar === 1 && <path d="M52 73 L60 90 L68 73" fill="none" stroke={c2} strokeWidth="3" />}
      {collar === 2 && <rect x="38" y="96" width="44" height="4" rx="2" fill={c2} opacity="0.85" />}
      <text x="60" y="113" textAnchor="middle" fontFamily="inherit" fontWeight="900" fontSize="17" fill={c2} opacity="0.95">
        {num}
      </text>
      {/* pescoço e cabeça (silhueta neutra) */}
      <rect x="53" y="60" width="14" height="16" rx="5" fill="#2b3348" />
      <ellipse cx="60" cy="44" rx="19" ry="22" fill="#2b3348" />
      {hair === 0 && <path d="M41 40 C42 22 78 20 79 40 C74 31 46 31 41 40 Z" fill="#141826" />}
      {hair === 1 && <path d="M41 42 C38 18 82 16 79 42 C77 30 43 30 41 42 Z" fill="#141826" />}
      {hair === 2 && <path d="M42 36 C48 24 72 24 78 36 C70 33 50 33 42 36 Z" fill="#141826" />}
      <ellipse cx="60" cy="47" rx="19" ry="22" fill="none" stroke="rgba(255,255,255,.06)" />
    </svg>
  )
}

// CARTA GERADA AUTOMATICAMENTE (image = 'auto'): moldura da raridade, nota, posição, escudo, nome e atleta ilustrado.
export default function AutoCard({ card }) {
  const club = card.club_id ? getClubById(card.club_id) : null
  const [c1, c2] = card.meta?.colors || club?.colors || ['#4b5878', '#e6ebf5']
  const meta = card.meta || {}
  return (
    <span className={`ac t-${card.tier}`}>
      <span className="ac-bg" aria-hidden="true" />
      <span className="ac-top">
        <span className="ac-ovr">
          <b>{card.overall}</b>
          <small>{card.position}</small>
          {meta.age != null && <small className="ac-age">{meta.age} anos</small>}
        </span>
        <span className="ac-badges">
          {club ? <ClubCrest clubId={club.id} size={22} /> : <span className="ac-clubtxt">{(meta.club_name || '').slice(0, 3).toUpperCase()}</span>}
          {meta.nationality && <span className="ac-nat">{meta.nationality}</span>}
        </span>
      </span>
      <Avatar card={card} c1={c1} c2={c2} />
      <span className={`ac-name ${card.name.length > 16 ? 'is-xlong' : card.name.length > 11 ? 'is-long' : ''}`}>
        <b>{card.name}</b>
        <small>{club?.name || meta.club_name || TIER_LABEL.basica}</small>
      </span>
      <span className="ac-tier">{TIER_LABEL[card.tier]}</span>
    </span>
  )
}
