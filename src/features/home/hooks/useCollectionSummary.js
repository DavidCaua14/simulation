import { useCallback, useEffect, useState } from 'react'
import { fetchCatalog, fetchCollection } from '../../cards/services/cardsApi'
import { tierOf } from '../../cards/data/tiers'

// Resumo da coleção para a Home: quantas cartas diferentes o jogador tem / total do catálogo
// e as 3 melhores (para a vitrine). Duas consultas leves; se falhar, a Home segue sem a vitrine.
export default function useCollectionSummary() {
  const [state, setState] = useState({ owned: 0, total: 0, top: [], ready: false })

  const load = useCallback(async () => {
    try {
      const [catalog, mine] = await Promise.all([fetchCatalog(), fetchCollection()])
      const owned = (mine || []).filter((m) => m.card)
      const ids = new Set([...(catalog || []).map((c) => c.id), ...owned.map((o) => o.card.id)])
      const top = owned
        .map((o) => o.card)
        .sort((a, b) => tierOf(b.tier).rank - tierOf(a.tier).rank || b.overall - a.overall)
        .slice(0, 3)
      setState({ owned: owned.length, total: ids.size, top, ready: true })
    } catch {
      setState((s) => ({ ...s, ready: true }))
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  return { ...state, reload: load }
}
