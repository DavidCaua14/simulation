import { useEffect, useState } from 'react'
import { dateLabel, negotiations } from '../services/careerWorldApi'
import { isSessionError } from '../../../lib/sessionRecovery'

// Renovações abertas no servidor: enquanto alguma está aqui, o contrato do atleta não vence (evolução 75).
export const OPEN_RENEWAL = new Set(['seller_review', 'club_pending', 'club_counter', 'player_pending', 'player_counter', 'player_accepted', 'agreed'])

export function renewalLabel(n) {
  if (n.status === 'player_counter') return { text: `Contraproposta do atleta · responda até ${dateLabel(n.expires_on)}`, mine: true }
  if (n.status === 'player_accepted') return { text: 'Aceitou · confirme o contrato', mine: true }
  if (n.status === 'agreed') return { text: 'Acordo fechado · registrando', mine: false }
  return { text: `Proposta enviada · resposta até ${dateLabel(n.reply_on || n.expires_on)}`, mine: false }
}

export function useOpenRenewals(version) {
  const [list, setList] = useState([])
  useEffect(() => {
    let alive = true
    negotiations()
      .then((rows) => alive && setList((rows || []).filter((n) => n.initiator === 'renewal' && OPEN_RENEWAL.has(n.status))))
      .catch((e) => { if (!isSessionError(e) && alive) setList([]) })
    return () => { alive = false }
  }, [version])
  return list
}
