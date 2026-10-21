import { supabase } from '../../lib/supabaseClient'
import { mapRowToCareer } from '../player/mapCareerRow'

// Vincula o jogador a um clube. Fica guardado na própria carreira
// (careers.club_id) — futuramente, trocar de clube é só chamar isso de
// novo com outro clubId, e o modo de simular partidas lê esse campo pra
// saber qual time o usuário defende agora.
export async function chooseClub({ careerId, clubId }) {
  if (!careerId || !clubId) {
    throw new Error('Carreira ou clube inválido.')
  }

  // A escolha passa por uma função do banco (choose_initial_club): o app não
  // pode mais trocar de clube por conta própria — só pelas propostas do modo Temporadas.
  const { error: rpcError } = await supabase.rpc('choose_initial_club', { p_club: clubId })
  if (rpcError) {
    console.error('[chooseClub]', rpcError)
    throw new Error('Não foi possível salvar o clube escolhido. Tente novamente.')
  }

  const { data, error } = await supabase.from('careers').select('*').eq('id', careerId).single()
  if (error) {
    console.error('[chooseClub]', error)
    throw new Error('Clube salvo, mas não foi possível recarregar sua carreira. Atualize a página.')
  }

  return mapRowToCareer(data)
}
