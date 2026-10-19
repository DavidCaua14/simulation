import { useCallback, useEffect, useState } from 'react'
import { fetchWallet } from '../services/predictionsApi'

const POLL_MS = 30000

// initial = { coins, energy } vindos do career.player (evita piscar vazio).
// Devolve sempre { coins, energy, refresh }: é seguro usar na Home e nos Palpites.
export default function useWallet(initial) {
  const [wallet, setWallet] = useState({
    coins: initial?.coins ?? null,
    energy: initial?.energy ?? null,
  })

  const refresh = useCallback(async () => {
    try {
      const data = await fetchWallet() // careers.coins / careers.energy da carreira ativa
      if (data) setWallet({ coins: data.coins, energy: data.energy })
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

  return { coins: wallet.coins, energy: wallet.energy, refresh }
}
