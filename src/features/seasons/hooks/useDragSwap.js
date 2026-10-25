import { useCallback, useEffect, useRef, useState } from 'react'

const THRESHOLD = 8 // px até virar "arrastar" (abaixo disso é um toque)

// Arrastar e soltar por ponteiro (dedo ou mouse). Cada alvo tem data-dnd="slot:ZAG1" | "bench:3" | "bench:new".
// Toque sem arrastar continua funcionando como clique (abre a lista de jogadores).
export default function useDragSwap({ onDrop, getPlayer }) {
  const [drag, setDrag] = useState(null) // { from, pid, x, y, over }
  const start = useRef(null)
  const justDragged = useRef(false)
  const cbs = useRef({ onDrop, getPlayer })
  cbs.current = { onDrop, getPlayer }

  const targetAt = (x, y) => {
    const el = document.elementFromPoint(x, y)?.closest?.('[data-dnd]')
    return el ? el.getAttribute('data-dnd') : null
  }

  // rolagem automática: arrastando perto da borda de cima/baixo, a tela rola (o banco fica abaixo do campo)
  const raf = useRef(0)
  const autoScroll = useCallback(() => {
    const s = start.current
    if (!s || !s.active || !s.scroller) return
    const r = s.scroller.getBoundingClientRect()
    const edge = 80
    let dy = 0
    if (s.lastY > r.bottom - edge) dy = Math.min(18, (s.lastY - (r.bottom - edge)) / 3)
    else if (s.lastY < r.top + edge) dy = -Math.min(18, (r.top + edge - s.lastY) / 3)
    if (dy) {
      s.scroller.scrollTop += dy
      const over = targetAt(s.lastX, s.lastY)
      setDrag((d) => (d ? { ...d, over: over !== s.from ? over : null } : d))
    }
    raf.current = requestAnimationFrame(autoScroll)
  }, [])

  useEffect(() => {
    function move(e) {
      const s = start.current
      if (!s) return
      s.lastX = e.clientX
      s.lastY = e.clientY
      const dx = e.clientX - s.x
      const dy = e.clientY - s.y
      if (!s.active) {
        if (Math.hypot(dx, dy) < THRESHOLD) return
        s.active = true
        cancelAnimationFrame(raf.current)
        raf.current = requestAnimationFrame(autoScroll)
      }
      e.preventDefault()
      const over = targetAt(e.clientX, e.clientY)
      setDrag({ from: s.from, pid: s.pid, x: e.clientX, y: e.clientY, over: over !== s.from ? over : null })
    }
    function up(e) {
      const s = start.current
      start.current = null
      cancelAnimationFrame(raf.current)
      if (!s) return
      if (s.active) {
        justDragged.current = true
        setTimeout(() => (justDragged.current = false), 50)
        const over = targetAt(e.clientX, e.clientY)
        setDrag(null)
        if (over && over !== s.from) cbs.current.onDrop(s.from, over)
      }
    }
    function cancel() {
      start.current = null
      cancelAnimationFrame(raf.current)
      setDrag(null)
    }
    window.addEventListener('pointermove', move, { passive: false })
    window.addEventListener('pointerup', up)
    window.addEventListener('pointercancel', cancel)
    return () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', cancel)
      cancelAnimationFrame(raf.current)
    }
  }, [autoScroll])

  // props para o elemento arrastável/alvo
  const bind = useCallback(
    (key, pid) => ({
      'data-dnd': key,
      onPointerDown: (e) => {
        if (!pid || (e.pointerType === 'mouse' && e.button !== 0)) return
        const scroller = e.currentTarget.closest('.sn-sheet-body, .sn-scroll') || document.scrollingElement
        start.current = { from: key, pid, x: e.clientX, y: e.clientY, lastX: e.clientX, lastY: e.clientY, active: false, scroller }
      },
      onClickCapture: (e) => {
        if (justDragged.current) {
          e.stopPropagation()
          e.preventDefault()
        }
      },
    }),
    [],
  )

  return { drag, bind, ghost: drag ? cbs.current.getPlayer(drag.pid) : null }
}
