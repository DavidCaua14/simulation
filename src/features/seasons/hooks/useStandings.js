import { useEffect, useState } from 'react'
import { fetchStandings } from '../services/managerApi'

const cache = new Map()

// Classificação calculada no banco, com os critérios de desempate oficiais de cada competição.
// `version` muda quando há jogos novos (invalida o cache).
export default function useStandings(seasonId, comp, group = null, version = 0) {
  const key = `${seasonId}|${comp}|${group || ''}|${version}`
  const [state, setState] = useState(() => ({ key, rows: cache.get(key) || null, error: '' }))

  useEffect(() => {
    if (!seasonId || !comp) return undefined
    let alive = true
    if (cache.has(key)) {
      setState({ key, rows: cache.get(key), error: '' })
      return undefined
    }
    setState((s) => ({ key, rows: s.key.startsWith(`${seasonId}|${comp}|${group || ''}|`) ? s.rows : null, error: '' }))
    fetchStandings(seasonId, comp, group)
      .then((rows) => {
        cache.set(key, rows)
        if (alive) setState({ key, rows, error: '' })
      })
      .catch((e) => alive && setState({ key, rows: [], error: e.message }))
    return () => {
      alive = false
    }
  }, [key, seasonId, comp, group])

  return state
}
