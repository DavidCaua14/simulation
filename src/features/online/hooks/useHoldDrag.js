import { useCallback, useEffect, useRef, useState } from 'react'

const HOLD_MS = 180 // na gaveta (lista que rola): segurar este tempo também descola a carta
const MOVE = 6 // no campo e no banco: mexer o dedo mais que isto já arrasta
const SLOP = 10 // na gaveta: mexer na vertical antes de descolar é rolagem

// SEGURAR E ARRASTAR (estilo eFootball). Toque sem mexer = clique normal (abre o menu do jogador).
// Campo e banco: encostou e mexeu o dedo, a carta já descola e segue o dedo (as cartas têm touch-action: none).
// Gaveta (rola na vertical): a carta descola ao puxar para o lado ou ao segurar ~0,2 s; puxar na vertical rola a lista.
// Ao soltar sobre outro lugar, chama onDrop(de, para).
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
  // descola a carta: ela passa a seguir o dedo
  const arm = useCallback((s) => {
    if (s.armed || st.current !== s) return
    if (s.timer) clearTimeout(s.timer)
    s.armed = true
    navigator.vibrate?.(15)
    cbs.current.onStart?.(s.from, s.pid)
    setDrag({ from: s.from, pid: s.pid, x: s.lastX, y: s.lastY, over: null })
    startScroll.current()
  }, [])

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
        const dx = Math.abs(e.clientX - s.x)
        const dy = Math.abs(e.clientY - s.y)
        if (s.instant) {
          if (Math.hypot(dx, dy) > MOVE) arm(s)
        } else if (dx > MOVE && dx > dy) arm(s) // gaveta: puxou para o lado
        else if (Math.hypot(dx, dy) > SLOP) clear() // é rolagem
        if (!s.armed) return
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
  }, [arm])

  const bind = useCallback(
    (key, pid) => ({
      'data-dnd': key,
      onPointerDown: (e) => {
        if (!pid || (e.pointerType === 'mouse' && e.button !== 0)) return
        const scroller = e.currentTarget.closest('.on-scroll') || document.scrollingElement
        // campo e banco (e mouse): arrasta assim que o dedo se mexe; gaveta no toque: puxar de lado ou segurar
        const instant = e.pointerType === 'mouse' || !key.startsWith('p:')
        const s = { from: key, pid, x: e.clientX, y: e.clientY, lastX: e.clientX, lastY: e.clientY, armed: false, scroller, instant }
        st.current = s
        if (!instant) s.timer = setTimeout(() => arm(s), HOLD_MS)
      },
      onClickCapture: (e) => {
        if (justDragged.current) {
          e.stopPropagation()
          e.preventDefault()
        }
      },
      onContextMenu: (e) => e.preventDefault(),
    }),
    [arm],
  )

  return { drag, bind }
}
