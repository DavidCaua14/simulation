// Opções do criador de personagem. Cada escolha aqui é uma "camada" do
// visual do jogador (appearance) — a mesma estrutura que, futuramente, vai
// receber acessórios da loja (boné, corte especial, etc.) como camadas
// extras por cima, sem precisar redesenhar nada disso.
export const SKIN_TONES = [
  { id: 'skin-1', hex: '#3d2314', label: 'Pele 1' },
  { id: 'skin-2', hex: '#5c3a24', label: 'Pele 2' },
  { id: 'skin-3', hex: '#8d5524', label: 'Pele 3' },
  { id: 'skin-4', hex: '#c68642', label: 'Pele 4' },
  { id: 'skin-5', hex: '#e0ac69', label: 'Pele 5' },
  { id: 'skin-6', hex: '#f1c27d', label: 'Pele 6' },
  { id: 'skin-7', hex: '#ffdbac', label: 'Pele 7' },
]

export const HAIR_STYLES = [
  { id: 'bald', label: 'Careca' },
  { id: 'buzz', label: 'Raspado' },
  { id: 'short', label: 'Curto' },
  { id: 'wavy', label: 'Ondulado' },
  { id: 'curly', label: 'Cacheado' },
]

export const HAIR_COLORS = [
  { id: 'hair-black', hex: '#141414', label: 'Preto' },
  { id: 'hair-darkbrown', hex: '#3b2a1e', label: 'Castanho escuro' },
  { id: 'hair-brown', hex: '#7a4a1e', label: 'Castanho' },
  { id: 'hair-blonde', hex: '#c9922f', label: 'Loiro' },
  { id: 'hair-red', hex: '#a13f2b', label: 'Ruivo' },
  { id: 'hair-gray', hex: '#9aa0a6', label: 'Grisalho' },
]

export const EYE_COLORS = [
  { id: 'eye-brown', hex: '#4a2f1a', label: 'Castanho' },
  { id: 'eye-black', hex: '#1c1c1c', label: 'Preto' },
  { id: 'eye-green', hex: '#3f7d4f', label: 'Verde' },
  { id: 'eye-blue', hex: '#3a6ea5', label: 'Azul' },
  { id: 'eye-amber', hex: '#a06a2e', label: 'Mel' },
]

export const BEARD_OPTIONS = [
  { id: false, label: 'Sem barba' },
  { id: true, label: 'Com barba' },
]

export const DEFAULT_APPEARANCE = {
  skin: SKIN_TONES[3].hex,
  hair: 'short',
  hairColor: HAIR_COLORS[1].hex,
  eyeColor: EYE_COLORS[0].hex,
  beard: false,
}
