import { useEffect, useState } from 'react'
import { supabase } from '../../../lib/supabaseClient'

// Formações (vagas com posição e coordenadas no campo) vêm do banco (sim_formations):
// o mesmo dado que o motor usa. Carrega uma vez por sessão.
let cache = null
let pending = null

async function load() {
  if (cache) return cache
  if (!pending) {
    pending = supabase
      .from('sim_formations')
      .select('id, name, sort, slots')
      .order('sort')
      .then(({ data, error }) => {
        if (error) throw error
        cache = { formations: data || [], byId: Object.fromEntries((data || []).map((f) => [f.id, f])) }
        return cache
      })
      .catch((e) => {
        pending = null
        throw e
      })
  }
  return pending
}

export default function useCatalog() {
  const [catalog, setCatalog] = useState(cache)
  const [error, setError] = useState('')
  useEffect(() => {
    let alive = true
    if (!cache) load().then((c) => alive && setCatalog(c)).catch((e) => alive && setError(e.message))
    return () => {
      alive = false
    }
  }, [])
  return { catalog, error }
}
