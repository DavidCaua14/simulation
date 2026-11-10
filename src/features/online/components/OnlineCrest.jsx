// Escudo do clube do modo online: desenhado com as cores do clube (não há escudo de catálogo para eles).
const light = (hex) => {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || '')
  if (!m) return false
  const n = parseInt(m[1], 16)
  return ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114 > 170
}

export default function OnlineCrest({ club, size = 40, className = '' }) {
  const a = club?.colors?.a || '#334155'
  const b = club?.colors?.b || '#ffffff'
  const ink = light(a) ? '#0b1220' : '#ffffff'
  const id = `oc${club?.id ?? 'x'}-${size}`
  return (
    <svg className={`on-crest ${className}`} width={size} height={size * 1.15} viewBox="0 0 100 115" role="img" aria-label={`Escudo do ${club?.name || 'clube'}`}>
      <defs>
        <clipPath id={`${id}c`}>
          <path d="M50 4 92 16v38c0 28-18 46-42 57C26 100 8 82 8 54V16Z" />
        </clipPath>
        <linearGradient id={`${id}g`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity=".35" />
          <stop offset=".5" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity=".25" />
        </linearGradient>
      </defs>
      <g clipPath={`url(#${id}c)`}>
        <rect width="100" height="115" fill={a} />
        <path d="M30 0h14v115H30zM56 0h14v115H56z" fill={b} opacity=".9" />
        <rect y="30" width="100" height="40" fill={a} />
        <rect width="100" height="115" fill={`url(#${id}g)`} />
      </g>
      <path d="M50 4 92 16v38c0 28-18 46-42 57C26 100 8 82 8 54V16Z" fill="none" stroke={b} strokeWidth="5" />
      <path d="M50 4 92 16v38c0 28-18 46-42 57C26 100 8 82 8 54V16Z" fill="none" stroke="rgba(0,0,0,.45)" strokeWidth="1.5" />
      <text x="50" y="58" textAnchor="middle" fontFamily="var(--font-display, sans-serif)" fontWeight="900" fontSize="26" fill={ink} stroke="rgba(0,0,0,.35)" strokeWidth=".8" paintOrder="stroke" letterSpacing="1">
        {club?.short || '?'}
      </text>
    </svg>
  )
}
