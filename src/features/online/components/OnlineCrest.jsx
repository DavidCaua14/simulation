// Escudo do clube do modo online: desenhado com as cores, o desenho e o formato escolhidos pelo técnico
// (colors: { a, b, pattern, shape }). Não há escudo de catálogo para esses clubes.
const light = (hex) => {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || '')
  if (!m) return false
  const n = parseInt(m[1], 16)
  return ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114 > 170
}

const OUTLINE = {
  shield: 'M50 4 92 16v38c0 28-18 46-42 57C26 100 8 82 8 54V16Z',
  round: 'M50 8a50 50 0 1 0 .01 0Z',
  diamond: 'M50 3 95 58 50 113 5 58Z',
}

function Pattern({ kind, a, b }) {
  switch (kind) {
    case 'hoops':
      return <path d="M0 14h100v16H0zM0 46h100v16H0zM0 78h100v16H0z" fill={b} opacity=".9" />
    case 'plain':
      return <path d="M0 0h100v12H0z" fill={b} opacity=".85" />
    case 'sash':
      return <path d="M-10 26 26-10 110 88 74 124Z" fill={b} opacity=".9" />
    case 'halves':
      return <path d="M50 0h50v115H50z" fill={b} opacity=".92" />
    case 'chevron':
      return <path d="M0 22 50 62 100 22v22L50 84 0 44Z" fill={b} opacity=".9" />
    default:
      return (
        <>
          <path d="M30 0h14v115H30zM56 0h14v115H56z" fill={b} opacity=".9" />
          <rect y="30" width="100" height="40" fill={a} />
        </>
      )
  }
}

export default function OnlineCrest({ club, size = 40, className = '' }) {
  const a = club?.colors?.a || '#334155'
  const b = club?.colors?.b || '#ffffff'
  const pattern = club?.colors?.pattern || 'stripes'
  const outline = OUTLINE[club?.colors?.shape] || OUTLINE.shield
  const band = pattern === 'halves' || pattern === 'sash' || pattern === 'hoops' || pattern === 'chevron'
  const ink = light(a) ? '#0b1220' : '#ffffff'
  const id = `oc${club?.id ?? 'x'}-${size}-${pattern}-${club?.colors?.shape || 's'}`
  return (
    <svg className={`on-crest ${className}`} width={size} height={size * 1.15} viewBox="0 0 100 115" role="img" aria-label={`Escudo do ${club?.name || 'clube'}`}>
      <defs>
        <clipPath id={`${id}c`}>
          <path d={outline} />
        </clipPath>
        <linearGradient id={`${id}g`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity=".35" />
          <stop offset=".5" stopColor="#fff" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity=".25" />
        </linearGradient>
      </defs>
      <g clipPath={`url(#${id}c)`}>
        <rect width="100" height="115" fill={a} />
        <Pattern kind={pattern} a={a} b={b} />
        {band && <rect x="14" y="40" width="72" height="30" rx="6" fill={a} />}
        <rect width="100" height="115" fill={`url(#${id}g)`} />
      </g>
      <path d={outline} fill="none" stroke={b} strokeWidth="5" />
      <path d={outline} fill="none" stroke="rgba(0,0,0,.45)" strokeWidth="1.5" />
      <text x="50" y="63" textAnchor="middle" fontFamily="var(--font-heading, sans-serif)" fontWeight="900" fontSize={(club?.short || '').length > 3 ? 21 : 26} fill={ink} stroke="rgba(0,0,0,.35)" strokeWidth=".8" paintOrder="stroke" letterSpacing="1">
        {club?.short || '?'}
      </text>
    </svg>
  )
}
