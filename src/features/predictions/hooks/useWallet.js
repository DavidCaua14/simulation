import { useCallback, useEffect, useState } from 'react'
// Ajuste o caminho conforme a pasta onde está o predictionsApi.js
import { fetchWallet } from '../../predictions/services/predictionsApi'

const POLL_MS = 30000

// initial = { coins, energy } vindos do career.player (evita piscar zerado)
export default function useWallet(initial) {
  const [wallet, setWallet] = useState(initial)

  const refresh = useCallback(async () => {
    try {
      const data = await fetchWallet() // careers.coins / careers.energy da carreira ativa
      if (data) setWallet(data)
    } catch {
      /* mantém o último valor */
    }
  }, [])

  useEffect(() => {
    refresh()
    const interval = setInterval(() => {
      if (!document.hidden) refresh()
    }, POLL_MS)
    const onVisible = () => {
      if (!document.hidden) refresh()
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      clearInterval(interval)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [refresh])

  return wallet
}