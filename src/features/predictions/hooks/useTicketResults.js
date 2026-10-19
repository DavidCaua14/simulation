import { useEffect, useRef } from 'react'
import { supabase } from '../../../lib/supabaseClient'

// Escuta (Realtime) os bilhetes DO USUÁRIO que mudam de status e chama onResult(ticket).
// O RLS da tabela garante que só chegam eventos dos próprios bilhetes.
export default function useTicketResults(onResult) {
  const callback = useRef(onResult)
  callback.current = onResult
  const seen = useRef(new Set())

  useEffect(() => {
    const channel = supabase
      .channel('tickets-realtime')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'tickets' }, (payload) => {
        const t = payload.new
        if (!t || t.status === 'pending' || seen.current.has(t.id)) return
        seen.current.add(t.id)
        callback.current?.(t)
      })
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [])
}
