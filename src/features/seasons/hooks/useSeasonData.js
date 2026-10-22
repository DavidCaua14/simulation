import { useCallback, useEffect, useRef, useState } from 'react'
import { fetchFixtures, fetchHub } from '../services/seasonsApi'

// Carrega TUDO do modo Temporadas de uma vez (resumo + todos os jogos dos 3 campeonatos).
// Depois disso, as abas só leem a memória: nenhuma troca de tela espera o banco.
// Depois de cada ação (jogar, aceitar proposta...) o refresh acontece "em silêncio",
// sem spinner: a tela continua mostrando os dados anteriores até os novos chegarem.
export default function useSeasonData() {
  const [hub, setHub] = useState(null)
  const [byComp, setByComp] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const alive = useRef(true)
  const seasonId = useRef(null)
  const reqId = useRef(0)

  const refresh = useCallback(async ({ silent = false } = {}) => {
    const mine = ++reqId.current
    if (!silent) setLoading(true)
    try {
      const loadFixtures = (id, comps) => Promise.all(comps.map((c) => fetchFixtures(id, c)))
      let h
      let lists
      let comps
      if (seasonId.current) {
        // já conhecemos a temporada: baixa resumo e jogos ao mesmo tempo
        const ids = ['brasileirao', 'copa_brasil', 'libertadores']
        ;[h, lists] = await Promise.all([fetchHub(), loadFixtures(seasonId.current, ids)])
        if (h.season.id !== seasonId.current) lists = await loadFixtures(h.season.id, ids) // começou outra temporada
        comps = ids
      } else {
        h = await fetchHub()
        comps = h.competitions.map((c) => c.id)
        lists = await loadFixtures(h.season.id, comps)
      }
      if (!alive.current || mine !== reqId.current) return null // chegou uma resposta mais nova
      seasonId.current = h.season.id
      setHub(h)
      setByComp(Object.fromEntries(comps.map((id, i) => [id, lists[i]])))
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

  return { hub, byComp, loading, error, refresh }
}
