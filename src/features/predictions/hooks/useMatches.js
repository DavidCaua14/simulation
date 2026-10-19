import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../../lib/supabaseClient' // ← ajuste o caminho
import { fetchLiveMatches, fetchMatchesForDay } from '../services/predictionsApi'
import { dayRange, isOverdue, sortMatches } from '../utils/matchUtils'

export function useNow(intervalMs = 15000) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs)
    return () => clearInterval(id)
  }, [intervalMs])
  return now
}

function belongsToView(match, view) {
  if (view === 'live') return match.status === 'live' || isOverdue(match, Date.now())
  const { start, end } = dayRange(view)
  const t = new Date(match.kickoff_at).getTime()
  return t >= new Date(start).getTime() && t < new Date(end).getTime()
}

/**
 * view: 'live' ou uma data "YYYY-MM-DD".
 * onEvent({ type: 'started' | 'finished', match }) dispara quando um jogo já carregado muda de status.
 */
export default function useMatches(view, onEvent) {
  const [matches, setMatches] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const statusRef = useRef(new Map())
  const viewRef = useRef(view)
  const eventRef = useRef(onEvent)
  viewRef.current = view
  eventRef.current = onEvent

  const load = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true)
      try {
        const data = view === 'live' ? await fetchLiveMatches() : await fetchMatchesForDay(view)
        data.forEach((m) => statusRef.current.set(m.id, m.status))
        setMatches(sortMatches(data))
        setError('')
      } catch (e) {
        if (!silent) setError('Não foi possível carregar os jogos.')
      } finally {
        if (!silent) setLoading(false)
      }
    },
    [view],
  )

  useEffect(() => {
    load()
    const id = setInterval(() => load(true), 60000) // rede de segurança caso o realtime caia
    return () => clearInterval(id)
  }, [load])

  useEffect(() => {
    const channel = supabase
      .channel('matches-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, (payload) => {
        const row = payload.new
        if (!row?.id) return
        const prev = statusRef.current.get(row.id)
        if (prev && prev !== row.status) {
          if (row.status === 'live') eventRef.current?.({ type: 'started', match: row })
          if (row.status === 'finished') eventRef.current?.({ type: 'finished', match: row })
        }
        statusRef.current.set(row.id, row.status)
        setMatches((cur) => {
          const rest = cur.filter((m) => m.id !== row.id)
          return belongsToView(row, viewRef.current) ? sortMatches([...rest, row]) : rest
        })
      })
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [])

  return { matches, loading, error, reload: () => load() }
}
