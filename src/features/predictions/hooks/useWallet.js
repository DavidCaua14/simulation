import { useCallback, useEffect, useState } from 'react'
import { fetchWallet } from '../services/predictionsApi'

export default function useWallet() {
  const [wallet, setWallet] = useState({ coins: null, energy: null })

  const refresh = useCallback(async () => {
    try {
      const data = await fetchWallet()
      if (data) setWallet(data)
    } catch {
      /* mantém o último valor */
    }
  }, [])

  useEffect(() => {
    refresh()
    const id = setInterval(refresh, 20000) // pega prêmios liquidados no servidor
    return () => clearInterval(id)
  }, [refresh])

  return { ...wallet, refresh }
}
