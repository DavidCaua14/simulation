import { isSessionError } from '../../../lib/sessionRecovery'
import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchCompetitions, fetchFixtures, fetchHub } from '../services/managerApi'
import { registerCompetitions, setSeasonCompetitions } from '../utils/seasonUtils'

// Carrega o modo Carreira de uma vez: o "hub" (treinador, clube, temporada, objetivos, mensagens...),
// o catálogo de competições e todos os jogos das competições da temporada (Brasil ou Inglaterra).
// Depois disso as abas só leem a memória.
// Depois de cada ação o refresh é "silencioso": a tela mantém os dados até os novos chegarem.
export default function useManagerData() {
  const [hub, setHub] = useState(null)
  const [byComp, setByComp] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const alive = useRef(true)
  const reqId = useRef(0)

  const refresh = useCallback(async ({ silent = false } = {}) => {
    const mine = ++reqId.current
    if (!silent) setLoading(true)
    try {
      const [h, comps] = await Promise.all([fetchHub(), fetchCompetitions()])
      registerCompetitions(comps)
      const ids = (h.competitions || []).map((c) => c.id)
      const lists = await Promise.all(ids.map((c) => fetchFixtures(h.season.id, c)))
      if (!alive.current || mine !== reqId.current) return null
      setSeasonCompetitions(ids)
      setHub(h)
      setByComp(Object.fromEntries(ids.map((id, i) => [id, lists[i]])))
      setError('')
      return h
    } catch (e) {
      if (isSessionError(e)) return null
      if (alive.current && mine === reqId.current) setError(e.message)
      return null
    } finally {
      if (alive.current && !silent && mine === reqId.current) setLoading(false)
    }
  }, [])

  useEffect(() => {
    alive.current = true
    refresh()
    return () => {
      alive.current = false
    }
  }, [refresh])

  return { hub, byComp, loading, error, refresh, setHub }
}
