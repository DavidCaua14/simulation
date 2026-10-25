import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchFixtures, fetchHub } from '../services/managerApi'

const COMPS = ['brasileirao', 'copa_brasil', 'libertadores']

// Carrega o modo Carreira de uma vez: o "hub" (treinador, clube, temporada, objetivos, mensagens...)
// e todos os jogos dos 3 campeonatos. Depois disso as abas só leem a memória.
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
      const h = await fetchHub()
      const lists = await Promise.all(COMPS.map((c) => fetchFixtures(h.season.id, c)))
      if (!alive.current || mine !== reqId.current) return null
      setHub(h)
      setByComp(Object.fromEntries(COMPS.map((id, i) => [id, lists[i]])))
      setError('')
      return h
    } catch (e) {
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
