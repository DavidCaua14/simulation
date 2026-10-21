import { useEffect, useState } from 'react'

// Milissegundos que faltam até `targetIso` (atualiza a cada 20s e avisa quando chega a zero).
export default function useCountdown(targetIso, onElapsed) {
  const target = targetIso ? Date.parse(targetIso) : null
  const [now, setNow] = useState(() => Date.now())

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 20000)
    return () => clearInterval(id)
  }, [])

  const remaining = target == null ? null : target - now
  const elapsed = remaining != null && remaining <= 0

  useEffect(() => {
    if (elapsed) onElapsed?.()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [elapsed, targetIso])

  return remaining
}
