import shieldBotafogo from '../assets/shield-botafogo.webp'
import shieldFluminense from '../assets/shield-fluminense.webp'
import shieldFlamengo from '../assets/shield-flamengo.webp'

// Propostas iniciais (hoje fixas; no futuro podem vir do banco, filtradas
// pelo país do jogador — ver countries.js).
export const CLUBS = [
  {
    id: 'botafogo',
    name: 'Botafogo',
    shield: shieldBotafogo,
    pitch: 'Tradição e um elenco jovem — espaço pra você ganhar minutos rápido.',
  },
  {
    id: 'fluminense',
    name: 'Fluminense',
    shield: shieldFluminense,
    pitch: 'Base forte em jogo de bola curta. Procuram reforço criativo.',
  },
  {
    id: 'flamengo',
    name: 'Flamengo',
    shield: shieldFlamengo,
    pitch: 'Maior torcida do país e pressão à altura. Só pra quem aguenta o peso da camisa.',
  },
]

export function getClubById(clubId) {
  return CLUBS.find((c) => c.id === clubId)
}
