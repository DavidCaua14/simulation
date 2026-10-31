import { isSessionError } from '../../../lib/sessionRecovery'
import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchCareerCalendar, fetchCompetitions, fetchFixtures, fetchHub } from '../services/managerApi'
import { registerCompetitions, setSeasonCompetitions } from '../utils/seasonUtils'

// Carrega o hub e uma prévia; o calendário completo vem apenas para a competição aberta.
// Versões por competição evitam repetir leituras de dados que não mudaram.
// Depois de cada ação o refresh é "silencioso": a tela mantém os dados até os novos chegarem.
export default function useManagerData(tab = 'home', selected = null) {
  const [hub, setHub] = useState(null)
  const [byComp, setByComp] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const alive = useRef(true)
  const reqId = useRef(0)
  const fixtureCache = useRef(new Map())
  const hasLoaded = useRef(false)

  const refresh = useCallback(async ({ silent = false } = {}) => {
    const mine = ++reqId.current
    if (!silent) setLoading(true)
    try {
      const [h, comps] = await Promise.all([fetchHub(), fetchCompetitions()])
      registerCompetitions(comps)
      const ids = (h.competitions || []).map((c) => c.id)
      const modern = h.calendar_versions != null
      const preview = modern ? await fetchCareerCalendar(tab === 'matches' ? 'mine' : 'preview') : null
      const lists = await Promise.all(ids.map(async (c) => {
        const key = `${h.career.id}:${h.season.id}:${c}`
        const version = h.calendar_versions?.[c]
        const cached = fixtureCache.current.get(key)
        if (version != null && cached?.version === version) return cached.rows
        const full = !modern || (tab === 'comps' && c === (selected || ids[0]))
        if (!full) return preview.filter((f) => f.competition_id === c)
        const rows = modern ? await fetchCareerCalendar('competition', c) : await fetchFixtures(h.season.id, c)
        if (alive.current && mine === reqId.current) fixtureCache.current.set(key, { version, rows })
        return rows
      }))
      if (!alive.current || mine !== reqId.current) return null
      setSeasonCompetitions(ids)
      hasLoaded.current = true
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
  }, [tab, selected])

  useEffect(() => {
    alive.current = true
    let cancelled = false
    queueMicrotask(() => { if (!cancelled) refresh({ silent: hasLoaded.current }) })
    return () => {
      cancelled = true
      alive.current = false
    }
  }, [refresh])

  return { hub, byComp, loading, error, refresh, setHub }
}
