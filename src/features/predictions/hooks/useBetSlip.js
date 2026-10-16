import { useMemo, useState } from 'react'
import { MAX_PICKS, slipMultiplier } from '../data/predictionRules'

// picks: { [matchId]: { match, result: 'home'|'draw'|'away'|null, btts: true|false|null } }
export default function useBetSlip() {
  const [picks, setPicks] = useState({})
  const pickList = useMemo(() => Object.values(picks), [picks])
  const multiplier = useMemo(() => slipMultiplier(pickList), [pickList])

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
