import { useEffect, useState } from 'react'
import { fetchInbox } from './inboxApi'

// Home: quantos itens novos ou para resgatar há na caixa de entrada. Atualiza quando a caixa muda.
export default function useInboxBadge() {
  const [count, setCount] = useState(0)
  useEffect(() => {
    let alive = true
    const load = () => fetchInbox().then((d) => {
      if (alive && d) setCount(Math.max(Number(d.unread) || 0, Number(d.claimable) || 0))
    }).catch(() => {})
    load()
    window.addEventListener('game:inbox', load)
    return () => {
      alive = false
      window.removeEventListener('game:inbox', load)
    }
  }, [])
  return count
}
