import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchHub } from '../services/seasonsApi'

// Carrega a tela principal do modo Temporadas direto do banco.
export default function useSeasonHub() {
  const [hub, setHub] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const alive = useRef(true)

  const reload = useCallback(async ({ silent = false } = {}) => {
    if (!silent) setLoading(true)
    try {
      const data = await fetchHub()
      if (!alive.current) return null
      setHub(data)
      setError('')
      return data
    } catch (e) {
      if (alive.current) setError(e.message)
      return null
    } finally {
      if (alive.current && !silent) setLoading(false)
    }
  }, [])

  useEffect(() => {
    alive.current = true
    reload()
    return () => {
      alive.current = false
    }
  }, [reload])

  return { hub, loading, error, reload }
}
