import { isSessionError } from '../../../lib/sessionRecovery'
import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchCareerCalendar, fetchCompetitions, fetchFixtures, fetchHub } from '../services/managerApi'
import { registerCompetitions, setSeasonCompetitions } from '../utils/seasonUtils'

// Carrega o hub e uma prévia; o calendário completo vem apenas para a competição aberta.
// Versões por competição evitam repetir leituras de dados que não mudaram.
// Depois de cada ação o refresh é "silencioso": a tela mantém os dados até os novos chegarem.
// pickDefault(hub, nextEvent): competição aberta quando nenhuma foi escolhida (a mesma que a tela de Torneios mostra).
export default function useManagerData(tab = 'home', selected = null, pickDefault = null) {
  const [hub, setHub] = useState(null)
  const [byComp, setByComp] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const alive = useRef(true)
  const reqId = useRef(0)
  const fixtureCache = useRef(new Map())
  const previewCache = useRef(new Map())
  const hubRef = useRef(null)
  const hasLoaded = useRef(false)

  // reuseHub: troca de aba reaproveita o hub já carregado; só ações (refresh) voltam ao servidor.
  const load = useCallback(async ({ silent = false, reuseHub = false } = {}) => {
    const mine = ++reqId.current
    if (!silent) setLoading(true)
    try {
      const cachedHub = reuseHub ? hubRef.current : null
      const [h, comps] = await Promise.all([cachedHub || fetchHub(), fetchCompetitions()])
      registerCompetitions(comps)
      const ids = (h.competitions || []).map((c) => c.id)
      const modern = h.calendar_versions != null
      const scope = tab === 'matches' ? 'mine' : 'preview'
      const previewKey = `${h.career.id}:${h.season.id}:${scope}:${JSON.stringify(h.calendar_versions || {})}`
      let preview = modern ? previewCache.current.get(previewKey) : null
      if (modern && !preview) {
        preview = await fetchCareerCalendar(scope)
        if (alive.current && mine === reqId.current) {
          previewCache.current.clear()
          previewCache.current.set(previewKey, preview)
        }
      }
      const lists = await Promise.all(ids.map(async (c) => {
        const key = `${h.career.id}:${h.season.id}:${c}`
        const version = h.calendar_versions?.[c]
        const cached = fixtureCache.current.get(key)
        if (version != null && cached?.version === version) return cached.rows
        const full = !modern || (tab === 'comps' && c === (selected || pickDefault?.(h, h.next_event) || ids[0]))
        if (!full) return preview.filter((f) => f.competition_id === c)
        const rows = modern ? await fetchCareerCalendar('competition', c) : await fetchFixtures(h.season.id, c)
        if (alive.current && mine === reqId.current) fixtureCache.current.set(key, { version, rows })
        return rows
      }))
      if (!alive.current || mine !== reqId.current) return null
      setSeasonCompetitions(ids)
      hasLoaded.current = true
      hubRef.current = h
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
  }, [tab, selected, pickDefault])

  const refresh = useCallback((opts = {}) => load({ ...opts, reuseHub: false }), [load])

  useEffect(() => {
    alive.current = true
    let cancelled = false
    queueMicrotask(() => { if (!cancelled) load({ silent: hasLoaded.current, reuseHub: hasLoaded.current }) })
    return () => {
      cancelled = true
      alive.current = false
    }
  }, [load])

  const setHubCached = useCallback((next) => {
    setHub((prev) => {
      const value = typeof next === 'function' ? next(prev) : next
      hubRef.current = value
      return value
    })
  }, [])

  return { hub, byComp, loading, error, refresh, setHub: setHubCached }
}
