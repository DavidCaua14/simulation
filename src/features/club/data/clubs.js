import shieldBotafogo from '../assets/shield-botafogo.webp'
import shieldFluminense from '../assets/shield-fluminense.webp'
import shieldFlamengo from '../assets/shield-flamengo.webp'
import { CLUB_CATALOG } from './clubCatalog'

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

// Qualquer clube do modo Temporadas (48). Os 3 iniciais mantêm o escudo em imagem;
// os demais usam o escudo desenhado (ClubCrest) com as cores do clube.
export function getClubById(clubId) {
  if (!clubId) return undefined
  const initial = CLUBS.find((c) => c.id === clubId)
  const catalog = CLUB_CATALOG[clubId]
  if (!initial && !catalog) return undefined
  return { ...catalog, ...initial }
}
