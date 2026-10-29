import { FaceAngry, FaceGrinning, FaceNeutral, FaceSlightlyFrowning, FaceSlightlySmiling } from 'lucide-react'

// Satisfação do atleta (0–100, calculada no banco pelos minutos, papel prometido e salários em dia).
// Mesmas faixas do rendimento: abaixo de 45 ele rende menos; abaixo de 30 pede para ser negociado.
export const MOODS = [
  { at: 80, id: 'joy', label: 'Muito satisfeito', Icon: FaceGrinning },
  { at: 60, id: 'happy', label: 'Satisfeito', Icon: FaceSlightlySmiling },
  { at: 45, id: 'neutral', label: 'Neutro', Icon: FaceNeutral },
  { at: 30, id: 'upset', label: 'Insatisfeito', Icon: FaceSlightlyFrowning },
  { at: -1, id: 'angry', label: 'Muito insatisfeito', Icon: FaceAngry },
]
export const moodOf = (morale) => (morale == null ? null : MOODS.find((m) => morale >= m.at))

