import { useCallback, useEffect, useRef, useState } from 'react'

const HOLD_MS = 280 // segurar este tempo "descola" a carta
const SLOP = 10 // mexer mais que isto antes de descolar é rolagem (não arrasta)

// SEGURAR E ARRASTAR (estilo eFootball). Toque curto = clique normal (abre o menu do jogador).
// Segurou ~0,3 s: a carta descola, segue o dedo e, ao soltar sobre outro lugar, chama onDrop(de, para).
// Antes de descolar, arrastar o dedo rola a tela normalmente (banco, gaveta e página).
// Alvos e origens levam data-dnd="slot:ZAG1" | "bench:3" | "bench:new" | "p:<id do jogador>".
export default function useHoldDrag({ onDrop, onStart }) {
  const [drag, setDrag] = useState(null) // { from, pid, x, y, over }
  const st = useRef(null) // { from, pid, x, y, timer, armed, scroller }
  const justDragged = useRef(false)
  const raf = useRef(0)
  const cbs = useRef({ onDrop, onStart })
  useEffect(() => {
    cbs.current = { onDrop, onStart }
  })

  // primeiro alvo sob o dedo (ignora a carta fantasma e desenhos por cima)
  const targetAt = (x, y) => {
    for (const el of document.elementsFromPoint(x, y)) {
      if (el.closest?.('.ef-ghost')) continue
      const t = el.closest?.('[data-dnd]')
      if (t) return t.getAttribute('data-dnd')
    }
    return null
  }

  const startScroll = useRef(() => {})

  useEffect(() => {
    // rolagem automática perto das bordas de cima e de baixo (o banco fica abaixo do campo)
    const tick = () => {
      const s = st.current
      if (!s?.armed) return
      // só rola depois que o dedo saiu de perto de onde a carta foi pega (o banco fica junto da borda de baixo)
      if (Math.hypot(s.lastX - s.x, s.lastY - s.y) < 60) {
        raf.current = requestAnimationFrame(tick)
        return
      }
      const el = s.scroller
      const whole = el === document.scrollingElement
      const top = whole ? 0 : el.getBoundingClientRect().top
      const bottom = whole ? window.innerHeight : el.getBoundingClientRect().bottom
      const edge = 70
      let dy = 0
      if (s.lastY > bottom - edge) dy = Math.min(16, (s.lastY - (bottom - edge)) / 3)
      else if (s.lastY < top + edge) dy = -Math.min(16, (top + edge - s.lastY) / 3)
      if (dy) el.scrollTop += dy
      raf.current = requestAnimationFrame(tick)
    }
    startScroll.current = () => {
      cancelAnimationFrame(raf.current)
      raf.current = requestAnimationFrame(tick)
    }
    const clear = () => {
      const s = st.current
      if (s?.timer) clearTimeout(s.timer)
      st.current = null
      cancelAnimationFrame(raf.current)
      setDrag(null)
    }
    const move = (e) => {
      const s = st.current
      if (!s) return
      s.lastX = e.clientX
      s.lastY = e.clientY
      if (!s.armed) {
        if (Math.hypot(e.clientX - s.x, e.clientY - s.y) > SLOP) clear() // é rolagem
        return
      }
      const over = targetAt(e.clientX, e.clientY)
      setDrag({ from: s.from, pid: s.pid, x: e.clientX, y: e.clientY, over: over !== s.from ? over : null })
    }
    const up = (e) => {
      const s = st.current
      if (!s) return
      if (s.armed) {
        justDragged.current = true
        setTimeout(() => (justDragged.current = false), 60)
        const over = targetAt(e.clientX, e.clientY)
        clear()
        if (over && over !== s.from) cbs.current.onDrop?.(s.from, over)
      } else clear()
    }
    // com a carta descolada, o dedo não rola a página
    const touchMove = (e) => {
      if (st.current?.armed && e.cancelable) e.preventDefault()
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    window.addEventListener('pointercancel', clear)
    window.addEventListener('touchmove', touchMove, { passive: false })
    return () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', clear)
      window.removeEventListener('touchmove', touchMove)
      cancelAnimationFrame(raf.current)
    }
  }, [])

  const bind = useCallback(
    (key, pid) => ({
      'data-dnd': key,
      onPointerDown: (e) => {
        if (!pid || (e.pointerType === 'mouse' && e.button !== 0)) return
        const scroller = e.currentTarget.closest('.on-scroll') || document.scrollingElement
        const s = { from: key, pid, x: e.clientX, y: e.clientY, lastX: e.clientX, lastY: e.clientY, armed: false, scroller }
        s.timer = setTimeout(() => {
          if (st.current !== s) return
          s.armed = true
          navigator.vibrate?.(15)
          cbs.current.onStart?.(key, pid)
          setDrag({ from: key, pid, x: s.lastX, y: s.lastY, over: null })
          startScroll.current()
        }, HOLD_MS)
        st.current = s
      },
      onClickCapture: (e) => {
        if (justDragged.current) {
          e.stopPropagation()
          e.preventDefault()
        }
      },
      onContextMenu: (e) => e.preventDefault(),
    }),
    [],
  )

  return { drag, bind }
}
