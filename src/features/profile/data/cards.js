// Raridades das cartas, da mais rara para a mais comum.
// Nomes pensados para futebol (familiar para quem joga): Bronze, Prata, Ouro, Elite, Lenda.
export const RARITIES = [
  { id: 'legend', label: 'Lenda', rank: 5, c1: '#ff9f43', c2: '#d6283a', glow: 'rgba(255,140,60,.55)' },
  { id: 'elite', label: 'Elite', rank: 4, c1: '#b57bff', c2: '#5b2bd6', glow: 'rgba(150,100,255,.5)' },
  { id: 'gold', label: 'Ouro', rank: 3, c1: '#f6d365', c2: '#c98b10', glow: 'rgba(240,190,60,.45)' },
  { id: 'silver', label: 'Prata', rank: 2, c1: '#e3e8ef', c2: '#8793a6', glow: 'rgba(190,200,215,.4)' },
  { id: 'bronze', label: 'Bronze', rank: 1, c1: '#d9996a', c2: '#8a4f26', glow: 'rgba(200,130,80,.4)' },
]

export function getRarity(id) {
  return RARITIES.find((r) => r.id === id) ?? RARITIES[RARITIES.length - 1]
}

// Carta: { id, name, rating, position, rarity }
// TODO: quando existir a tabela de cartas, troque por uma consulta ao banco
//       (somente as cartas que o jogador escolheu expor na vitrine).
export const SAMPLE_CARDS = [
  { id: 's1', name: 'R. Falcão', rating: 96, position: 'ATA', rarity: 'legend' },
  { id: 's2', name: 'M. Duarte', rating: 91, position: 'MEI', rarity: 'elite' },
  { id: 's3', name: 'T. Alcântara', rating: 88, position: 'ZAG', rarity: 'elite' },
  { id: 's4', name: 'L. Barreto', rating: 84, position: 'LAT', rarity: 'gold' },
  { id: 's5', name: 'C. Nogueira', rating: 82, position: 'VOL', rarity: 'gold' },
  { id: 's6', name: 'J. Moura', rating: 76, position: 'GOL', rarity: 'silver' },
  { id: 's7', name: 'P. Vidal', rating: 71, position: 'ATA', rarity: 'silver' },
  { id: 's8', name: 'E. Lima', rating: 64, position: 'MEI', rarity: 'bronze' },
]

// false = vitrine vazia (estado real do jogo hoje). Troque para true para pré-visualizar o layout.
export const USE_SAMPLE_CARDS = false

export function getShowcaseCards() {
  return USE_SAMPLE_CARDS ? SAMPLE_CARDS : []
}
