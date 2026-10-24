import { useCallback, useEffect, useRef, useState } from 'react'
import { claimDaily, fetchPendingBoxes } from '../services/cardsApi'

// Caixa de entrada: lista de caixas esperando para serem abertas.
// claim: true -> ao montar, pede ao banco as caixas de boas-vindas/do dia (idempotente: repetir não duplica).
// `granted` = resposta da entrega (quantas caixas novas chegaram agora), útil para o aviso da Home.
export default function useInbox({ claim = false } = {}) {
  const [boxes, setBoxes] = useState([])
  const [loading, setLoading] = useState(true)
  const [granted, setGranted] = useState(null)
  const alive = useRef(true)
  const claimed = useRef(false)

  const refresh = useCallback(async () => {
    try {
      const list = await fetchPendingBoxes()
      if (alive.current) setBoxes(list || [])
      return list || []
    } catch {
      return null // mantém a lista anterior
    } finally {
      if (alive.current) setLoading(false)
    }
  }, [])

  useEffect(() => {
    alive.current = true
    ;(async () => {
      if (claim && !claimed.current) {
        claimed.current = true
        try {
          const r = await claimDaily()
          if (alive.current && r?.granted > 0) setGranted(r)
        } catch {
          /* sem internet / função ainda não instalada: a Home segue normal */
        }
      }
      refresh()
    })()
    return () => {
      alive.current = false
    }
  }, [claim, refresh])

  return { boxes, count: boxes.length, loading, granted, clearGranted: () => setGranted(null), refresh }
}
