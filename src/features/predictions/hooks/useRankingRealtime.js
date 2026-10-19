import { useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabaseClient'
// Ajuste o caminho conforme a pasta onde está o predictionsApi.js
import { fetchLeaderboard } from '../../predictions/services/predictionsApi'

const LIMIT = 10
const POLL_MS = 20000 // ranking só muda quando settle_tickets roda; 20s é suficiente
const SETTLE_DELAY_MS = 3000

// Retorna { entries, status } com status: 'loading' | 'ready' | 'error'
export default function useRankingRealtime() {
  const [state, setState] = useState({ entries: [], status: 'loading' })

  useEffect(() => {
    let active = true
    let timer = null

    async function load() {
      try {
        const rows = await fetchLeaderboard() // RPC get_prediction_leaderboard (50 linhas)
        if (!active) return
        setState({
          status: 'ready',
          entries: (rows ?? []).slice(0, LIMIT).map((r) => ({
            id: r.career_id,
            position: Number(r.position),
            nickname: r.nickname,
            points: r.points,
          })),
        })
      } catch {
        if (active) setState((prev) => ({ ...prev, status: prev.entries.length ? 'ready' : 'error' }))
      }
    }

    load()

    const interval = setInterval(() => {
      if (!document.hidden) load()
    }, POLL_MS)
    const onVisible = () => {
      if (!document.hidden) load()
    }
    document.addEventListener('visibilitychange', onVisible)

    // Só `matches` está na publicação realtime (e é legível por todos).
    // Quando um jogo termina, o servidor liquida os bilhetes logo depois: refaz a busca.
    const channel = supabase
      ? supabase
          .channel('ranking-refresh')
          .on(
            'postgres_changes',
            { event: 'UPDATE', schema: 'public', table: 'matches', filter: 'status=eq.finished' },
            () => {
              clearTimeout(timer)
              timer = setTimeout(load, SETTLE_DELAY_MS)
            },
          )
          .subscribe()
      : null

    return () => {
      active = false
      clearTimeout(timer)
      clearInterval(interval)
      document.removeEventListener('visibilitychange', onVisible)
      if (channel) supabase.removeChannel(channel)
    }
  }, [])

  return state
}