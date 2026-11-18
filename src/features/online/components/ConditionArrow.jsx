// SETA DE CONDIÇÃO (como no PES): 1 vermelha ↓, 2 laranja ↘, 3 amarela →, 4 verde ↗, 5 azul ↑.
// Vale para a próxima partida e muda ao fim de cada jogo do clube.
import { ARROWS } from '../conditions'

export default function ConditionArrow({ arrow = 3, size = 16, className = '' }) {
  const a = ARROWS[arrow] || ARROWS[3]
  return (
    <svg className={`cond-arrow ${className}`} width={size} height={size} viewBox="0 0 24 24" role="img" aria-label={`Condição ${a.label}`}>
      <rect width="24" height="24" rx="4" fill="#0b1020" />
      <g transform={`rotate(${a.rot} 12 12)`}>
        <path d="M4 9.5h9V5l7 7-7 7v-4.5H4z" fill={a.color} />
      </g>
    </svg>
  )
}
