import { Angry, Frown, Meh, Smile } from 'lucide-react'
import { moraleState } from '../utils/managerUtils'
import './mood.css'

const ICON = { happy: Smile, neutral: Meh, unhappy: Frown, angry: Angry }

// Rostinho de satisfação do atleta: verde satisfeito (80+), amarelo neutro (60–79),
// laranja insatisfeito (35–59), vermelho revoltado (abaixo de 35).
export default function MoodFace({ morale, size = 12, className = '' }) {
  const st = moraleState(morale)
  if (!st) return null
  const Icon = ICON[st.id]
  const text = `${st.label} · moral ${Math.round(morale)}%`
  return (
    <i className={`mood-face m-${st.id} ${className}`} title={text} aria-label={text} role="img">
      <Icon size={size} strokeWidth={2.6} />
    </i>
  )
}

// Legenda curta das faces (tela de time e escalação).
export function MoodLegend() {
  return (
    <p className="mood-legend" aria-label="Legenda da satisfação">
      <span><MoodFace morale={90} /> Satisfeito 80+</span>
      <span><MoodFace morale={70} /> Neutro</span>
      <span><MoodFace morale={45} /> Insatisfeito</span>
      <span><MoodFace morale={20} /> Revoltado</span>
    </p>
  )
}
