// Avatares padrão: bustos de jogador (rosto + uniforme de treino), no
// mesmo espírito de ícone esportivo genérico usado em apps de futebol —
// desenhados aqui mesmo (SVG próprio, sem depender de nenhuma imagem ou
// biblioteca externa), variando tom de pele, cabelo e barba.
export const AVATAR_PRESETS = [
  { id: 'a1', skin: '#8d5524', hair: 'short', hairColor: '#141414', beard: false },
  { id: 'a2', skin: '#c68642', hair: 'buzz', hairColor: '#0d0d0d', beard: true },
  { id: 'a3', skin: '#e0ac69', hair: 'wavy', hairColor: '#3b2a1e', beard: false },
  { id: 'a4', skin: '#f1c27d', hair: 'short', hairColor: '#7a4a1e', beard: true },
  { id: 'a5', skin: '#ffdbac', hair: 'buzz', hairColor: '#c9922f', beard: false },
  { id: 'a6', skin: '#8d5524', hair: 'curly', hairColor: '#0d0d0d', beard: false },
  { id: 'a7', skin: '#c68642', hair: 'short', hairColor: '#1e1e1e', beard: false },
  { id: 'a8', skin: '#e0ac69', hair: 'curly', hairColor: '#2b1c10', beard: true },
]

export function getAvatarPresetById(avatarId) {
  return AVATAR_PRESETS.find((a) => a.id === avatarId)
}
