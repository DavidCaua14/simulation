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

  const { data, error } = await supabase
    .from('careers')
    .update({ club_id: clubId })
    .eq('id', careerId)
    .select()
    .single()

  if (error) {
    console.error('[chooseClub]', error)
    throw new Error('Não foi possível salvar o clube escolhido. Tente novamente.')
  }

  return mapRowToCareer(data)
}
