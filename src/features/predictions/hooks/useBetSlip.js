import { useEffect, useMemo, useState } from 'react'
import { MAX_PICKS, slipMultiplier } from '../data/predictionRules'

const STORAGE_KEY = 'predictions_slip_v1'

// O bilhete em montagem sobrevive a sair da tela e a recarregar a página.
function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}')
    const out = {}
    for (const [id, p] of Object.entries(raw)) {
      if (p?.match?.id && p.match.kickoff_at && (p.result != null || p.btts != null)) out[id] = p
    }
    return out
  } catch {
    return {}
  }
}

// picks: { [matchId]: { match, result: 'home'|'draw'|'away'|null, btts: true|false|null } }
export default function useBetSlip() {
  const [picks, setPicks] = useState(load)
  const pickList = useMemo(() => Object.values(picks), [picks])
  const multiplier = useMemo(() => slipMultiplier(pickList), [pickList])

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(picks))
    } catch {
      /* armazenamento indisponível: segue sem persistir */
    }
  }, [picks])

  // retorna false se o bilhete já está cheio
  function update(match, patch) {
    if (!picks[match.id] && pickList.length >= MAX_PICKS) return false
    setPicks((prev) => {
      const cur = prev[match.id] || { result: null, btts: null }
      const next = { ...cur, ...patch }
      const copy = { ...prev }
      if (next.result == null && next.btts == null) delete copy[match.id]
      else copy[match.id] = { match, result: next.result, btts: next.btts }
      return copy
    })
    return true
  }

  return {
    picks,
    pickList,
    multiplier,
    count: pickList.length,
    toggleResult: (match, result) => update(match, { result: picks[match.id]?.result === result ? null : result }),
    toggleBtts: (match, value) => update(match, { btts: picks[match.id]?.btts === value ? null : value }),
    remove: (matchId) =>
      setPicks((prev) => {
        const copy = { ...prev }
        delete copy[matchId]
        return copy
      }),
    removeMany: (ids) =>
      setPicks((prev) => {
        const copy = { ...prev }
        ids.forEach((id) => delete copy[id])
        return copy
      }),
    clear: () => setPicks({}),
  }
}
