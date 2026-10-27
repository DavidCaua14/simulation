import { useState } from 'react'
import { COMP_THEME } from '../utils/seasonUtils'
import { COMP_EMBLEMS } from '../../club/data/competitionEmblems'

// Emblema do campeonato. Com o logo oficial (public/competitions), ele aparece numa placa clara — assim logos
// escuros (Champions, Série A) ficam legíveis nos dois temas. Sem logo (ou se a imagem falhar), cai no escudo
// desenhado com as cores do torneio.
export default function CompEmblem({ comp, size = 40, dim = false }) {
  const [failed, setFailed] = useState(false)
  const file = COMP_EMBLEMS[comp]
  const t = COMP_THEME[comp] || { c1: '#2b3445', c2: '#c9d2e3', code: '?' }

  if (file && !failed) {
    return (
      <span className={`ce ce-logo ${dim ? 'is-dim' : ''}`} style={{ width: size, height: size * 1.12, padding: Math.max(2, Math.round(size * 0.1)), '--ce-accent': t.c1 }}>
        <img src={`${import.meta.env.BASE_URL}competitions/${file}`} alt="" decoding="async" draggable="false" onError={() => setFailed(true)} />
      </span>
    )
  }

  const id = `ce-${comp}`
  return (
    <svg className={`ce ${dim ? 'is-dim' : ''}`} width={size} height={size * 1.12} viewBox="0 0 40 45" role="img" aria-hidden="true">
      <defs>
        <linearGradient id={`${id}-g`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" style={{ stopColor: t.c1 }} />
          <stop offset="1" style={{ stopColor: `color-mix(in srgb, ${t.c1} 55%, #000)` }} />
        </linearGradient>
        <linearGradient id={`${id}-r`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" style={{ stopColor: '#fff6cf' }} />
          <stop offset=".5" style={{ stopColor: t.c2 }} />
          <stop offset="1" style={{ stopColor: `color-mix(in srgb, ${t.c2} 55%, #000)` }} />
        </linearGradient>
      </defs>
      <path d="M20 1.5 L37 7 V22 C37 33 29.5 40 20 43.5 C10.5 40 3 33 3 22 V7 Z" fill={`url(#${id}-g)`} stroke={`url(#${id}-r)`} strokeWidth="2.6" />
      <path d="M20 8 l1.9 3.9 4.3.6-3.1 3 .7 4.3L20 17.8l-3.8 2 .7-4.3-3.1-3 4.3-.6z" fill={t.c2} />
      <text x="20" y="34" textAnchor="middle" fontSize={(t.code || '').length > 2 ? 9.5 : 12} fontWeight="800" fill="#fff" fontFamily="Saira Condensed, Rajdhani, sans-serif" letterSpacing=".5">
        {t.code}
      </text>
    </svg>
  )
}
