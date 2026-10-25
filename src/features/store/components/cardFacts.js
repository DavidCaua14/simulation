import { getClubById } from '../../club/data/clubs'

const KIND = { atual: 'Temporada atual', lenda: 'Lenda' }
const NAT = { BRA: 'Brasil', ARG: 'Argentina', URU: 'Uruguai', ENG: 'Inglaterra', FRA: 'França', ESP: 'Espanha', POR: 'Portugal',
  GER: 'Alemanha', ITA: 'Itália', NED: 'Holanda', BEL: 'Bélgica', COL: 'Colômbia', CHI: 'Chile', PAR: 'Paraguai', ECU: 'Equador' }

// "Atributos relevantes" da carta para a loja e o mercado: nota, posição, clube, nacionalidade e tipo.
export function cardFacts(card) {
  const meta = card?.meta || {}
  const club = card?.club_id ? getClubById(card.club_id) : null
  return {
    overall: card?.overall,
    position: card?.position || '—',
    club: club?.name || meta.club_name || '—',
    nationality: NAT[meta.nationality] || meta.nationality || '—',
    kind: KIND[meta.kind] || '',
  }
}
