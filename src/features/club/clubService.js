import { supabase } from '../../lib/supabaseClient'
import { mapRowToCareer } from '../player/mapCareerRow'

// Propostas iniciais: 2 clubes sorteados entre os mais fracos da Série A. O sorteio acontece
// UMA vez, no banco (função get_initial_offers), e fica gravado: recarregar a página mostra as
// mesmas propostas, então não dá para "re-sortear" até aparecer um clube melhor.
export async function fetchInitialOffers() {
  const { data, error } = await supabase.rpc('get_initial_offers')
  if (error) {
    console.error('[fetchInitialOffers]', error)
    throw new Error('Não foi possível carregar as propostas. Tente novamente.')
  }
  return data || []
}

// Aceita uma das propostas iniciais. O clube e as luvas de assinatura são aplicados pelo banco
// (choose_initial_club); depois trocar de clube só pelas propostas do modo Temporadas.
export async function chooseClub({ careerId, offerId }) {
  if (!careerId || !offerId) {
    throw new Error('Carreira ou proposta inválida.')
  }

  const { error: rpcError } = await supabase.rpc('choose_initial_club', { p_offer: offerId })
  if (rpcError) {
    console.error('[chooseClub]', rpcError)
    throw new Error('Não foi possível fechar com o clube escolhido. Tente novamente.')
  }

  const { data, error } = await supabase.from('careers').select('*').eq('id', careerId).single()
  if (error) {
    console.error('[chooseClub]', error)
    throw new Error('Clube salvo, mas não foi possível recarregar sua carreira. Atualize a página.')
  }

  return mapRowToCareer(data)
}
