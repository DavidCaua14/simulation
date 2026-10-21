import { getClubById } from '../data/clubs'

// Escolhe preto/branco para o texto da sigla conforme o brilho da cor de fundo.
function readableOn(hex) {
  const n = parseInt(hex.slice(1), 16)
  const lum = (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255
  return lum > 0.62 ? '#111111' : '#ffffff'
}

// Escudo do clube: usa a imagem quando existe (os 3 clubes iniciais);
// para os outros desenha um escudo com as cores e a sigla do clube.
export default function ClubCrest({ clubId, size = 40, className = '' }) {
  const club = getClubById(clubId)
  const style = { width: size, height: size }
  if (!club) return <span className={`crest ${className}`} style={style} aria-hidden="true" />

  if (club.shield) {
    return <img className={`crest ${className}`} style={style} src={club.shield} alt={club.name} />
  }

  const [c1, c2] = club.colors || ['#444444', '#bbbbbb']
  const gid = `crest-${club.id}`
  return (
    <svg className={`crest ${className}`} style={style} viewBox="0 0 48 56" role="img" aria-label={club.name}>
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={c1} />
          <stop offset="0.62" stopColor={c1} />
          <stop offset="0.62" stopColor={c2} />
          <stop offset="1" stopColor={c2} />
        </linearGradient>
      </defs>
      <path d="M24 2 L44 8 V28 C44 42 35 50 24 54 C13 50 4 42 4 28 V8 Z" fill={`url(#${gid})`} stroke="rgba(0,0,0,.45)" strokeWidth="2" />
      <path d="M24 2 L44 8 V28 C44 42 35 50 24 54 C13 50 4 42 4 28 V8 Z" fill="none" stroke="rgba(255,255,255,.35)" strokeWidth="1" transform="translate(0.5 0.5) scale(.98)" />
      <text x="24" y="31" textAnchor="middle" fontSize="15" fontWeight="800" fontFamily="Rajdhani, Inter, sans-serif"
        fill={readableOn(c1)} stroke={readableOn(c1) === '#ffffff' ? 'rgba(0,0,0,.35)' : 'rgba(255,255,255,.4)'} strokeWidth=".4">
        {club.short}
      </text>
    </svg>
  )
}
