import { useEffect, useRef, useState } from 'react'
import { isSessionError } from '../../../lib/sessionRecovery'
import { advanceWorld, requestId } from '../services/careerWorldApi'
import { createWorldSimulation } from '../utils/worldSimulation'

export default function useWorldSimulation({ hub, refresh, paused }) {
  const snapshot = useRef({ hub, paused })
  const [status, setStatus] = useState('idle')
  useEffect(() => { snapshot.current = { hub, paused } }, [hub, paused])
  useEffect(() => {
    let alive = true
    let timer
    let failures = 0
    let sessionEnded = false
    const simulation = createWorldSimulation({ advance: advanceWorld, refresh, requestId })
    async function tick() {
      let wait = 350
      try {
        const current = snapshot.current
        if (current.paused || document.hidden || !simulation.hasWork(current.hub)) return
        const work = simulation.tick(current.hub, current.paused)
        // Status is informational: the remaining tabs stay available during a batch.
        setStatus('syncing')
        await work
        failures = 0
        if (alive) setStatus('idle')
      } catch (error) {
        if (isSessionError(error)) { sessionEnded = true; return }
        failures++
        wait = Math.min(30000, 1000 * 2 ** Math.min(failures, 5))
        if (alive) setStatus('retrying')
      } finally {
        if (alive && !sessionEnded) timer = setTimeout(tick, wait)
      }
    }
    timer = setTimeout(tick, 150)
    return () => { alive = false; clearTimeout(timer) }
  }, [refresh])
  return status
}
