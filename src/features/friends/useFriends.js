import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabaseClient'
import { fetchFriends } from './friendsApi'

const POLL_MS = 30000

// Lista de amigos/convites, atualizada em tempo real (Supabase Realtime na tabela friendships, só as linhas
// do próprio usuário pela RLS) e, por garantia, a cada 30 s e quando a aba volta a ficar visível.
export default function useFriends() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const timer = useRef(null)
  const refresh = useCallback(async () => {
    try {
      setData(await fetchFriends())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])

  useEffect(() => {
    refresh()
    const poll = setInterval(() => !document.hidden && refresh(), POLL_MS)
    const onVis = () => !document.hidden && refresh()
    document.addEventListener('visibilitychange', onVis)
    const ch = supabase
      .channel('friends-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'friendships' }, () => {
        clearTimeout(timer.current)
        timer.current = setTimeout(refresh, 300)
      })
      .subscribe()
    return () => {
      clearInterval(poll)
      clearTimeout(timer.current)
      document.removeEventListener('visibilitychange', onVis)
      supabase.removeChannel(ch)
    }
  }, [refresh])

  return { data, error, refresh }
}
