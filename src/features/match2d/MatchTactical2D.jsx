import { useEffect, useMemo, useRef, useState } from 'react'
import ClubCrest from '../club/components/ClubCrest'
import { getClubById } from '../club/data/clubs'
import { createDirector } from './director'
import { BALL_D, BANNER_ART, BANNER_TEXT, FIELD, KEEPERS, PLAYER_D, loadKit2d, pickMarkers } from './kit2d'
import './tactical2d.css'

// Orientação do campo: preferência só deste navegador.
function readOrientation() {
  try {
    return window.localStorage.getItem('sim.field2d') === 'v' ? 'v' : 'h'
  } catch {
    return 'h'
  }
}

// Transformação única mundo (105 × 68) → tela, para campo, atletas, bola e textos.
function fieldRect(cw, ch, o) {
  const [, , vw, vh] = FIELD[o].view
  const aspect = vw / vh
  let w = cw
  let h = cw / aspect
  if (h > ch) {
    h = ch
    w = ch * aspect
  }
  const left = (cw - w) / 2
  const top = (ch - h) / 2
  const m = w / vw // pixels por metro
  const at =
    o === 'h'
      ? (x, y) => [left + ((x + 6) / 117) * w, top + ((y + 5) / 78) * h]
      : (x, y) => [left + ((y + 5) / 78) * w, top + ((111 - x) / 117) * h]
  return { left, top, w, h, m, at }
}

// onHold(minuto|null): o relógio da partida não passa do minuto de um lance que o campo ainda está mostrando.
// onReveal(seqs): lances que o campo acabou de mostrar (gol na rede, defesa, cartão) — o placar conta na hora.
// clubs (opcional): clubes fora do catálogo (modo online) → { home: {name, short, colors:[a,b]}, away, crest: (side) => elemento }
export default function MatchTactical2D({ data, catalog, clock, events, paused, speed = 1, minute, score, finished, clockLabel, userSide, onHold, onReveal, clubs }) {
  const wrap = useRef(null)
  const canvas = useRef(null)
  const imgs = useRef(null)
  const seen = useRef(new Set())
  const [ready, setReady] = useState(false)
  const [failed, setFailed] = useState(false)
  const [banner, setBanner] = useState(null)
  const [orient, setOrient] = useState(readOrientation)
  const live = useRef({ paused, speed, orient })
  useEffect(() => {
    live.current = { paused, speed, orient }
  }, [paused, speed, orient])

  // getClubById devolve um objeto novo a cada chamada: a escolha dos marcadores depende só dos ids
  const home = clubs?.home || getClubById(data.home)
  const away = clubs?.away || getClubById(data.away)
  const hc = (clubs?.home?.colors || getClubById(data.home)?.colors || []).join()
  const ac = (clubs?.away?.colors || getClubById(data.away)?.colors || []).join()
  const markers = useMemo(() => pickMarkers(hc ? hc.split(',') : undefined, ac ? ac.split(',') : undefined), [hc, ac])
  const view = useRef({ markers, userSide })
  useEffect(() => {
    view.current = { markers, userSide }
  }, [markers, userSide])

  useEffect(() => {
    let alive = true
    loadKit2d()
      .then((k) => {
        if (!alive) return
        imgs.current = k
        setReady(true)
      })
      .catch(() => alive && setFailed(true))
    return () => {
      alive = false
    }
  }, [])

  // diretor (só apresentação): criado uma vez por partida
  const [dir] = useState(() => {
    const d = createDirector({ formations: catalog?.byId, homeId: data.home, awayId: data.away })
    d.sync(data.players || [], data.formation)
    d.kickoff('h')
    return d
  })
  const director = useRef(dir)
  useEffect(() => {
    if (import.meta.env.DEV) window.__campo2d = dir // inspeção na prévia local
  }, [dir])
  useEffect(() => {
    director.current?.sync(data.players || [], data.formation)
  }, [data.players, data.formation])
  useEffect(() => {
    const poss = data.stats?.poss?.[0]
    director.current?.setPossession(poss ? poss / 100 : 0.5)
  }, [data.stats])
  useEffect(() => {
    const m = minute ?? 0
    director.current?.setHalf(m < 45 ? 1 : m < 90 ? 2 : m < 105 ? 1 : 2)
  }, [minute])

  // eventos reais → jogadas. Lances anteriores à abertura (partida retomada) não são reencenados.
  const startClock = useRef(clock)
  useEffect(() => {
    const d = director.current
    if (!d) return
    for (const e of events) {
      if (seen.current.has(e.seq)) continue
      seen.current.add(e.seq)
      if (e.minute < startClock.current - 0.5) continue
      d.enqueue(e)
    }
  }, [events])

  const holdRef = useRef(onHold)
  const revealRef = useRef(onReveal)
  useEffect(() => {
    holdRef.current = onHold
    revealRef.current = onReveal
  }, [onHold, onReveal])
  useEffect(() => {
    if (failed) {
      director.current?.releaseAll()
      holdRef.current?.(null)
    }
    return () => holdRef.current?.(null)
  }, [failed])

  // laço: simulação visual com deltaTime e desenho. Criado UMA vez (depende só de a arte estar pronta);
  // o resto chega por refs, para o canvas nunca ser recriado nem apagado no meio da partida.
  const lastBannerRef = useRef(null)
  useEffect(() => {
    if (!ready) return undefined
    const cv = canvas.current
    const g = cv.getContext('2d')
    let raf = 0
    let last = performance.now()
    let lastHold
    let dpr = 1
    let reported = false

    // mudar width/height apaga o canvas: só quando o tamanho muda de fato
    const resize = () => {
      const r = wrap.current.getBoundingClientRect()
      dpr = Math.min(2, window.devicePixelRatio || 1)
      const w = Math.max(1, Math.round(r.width * dpr))
      const h = Math.max(1, Math.round(r.height * dpr))
      if (cv.width !== w) cv.width = w
      if (cv.height !== h) cv.height = h
    }
    resize()
    const ro = new ResizeObserver(resize)
    ro.observe(wrap.current)

    const pill = (text, x, y, size, bg) => {
      g.font = `700 ${size}px Inter, system-ui, sans-serif`
      const w = g.measureText(text).width + size * 0.9
      const h = size * 1.45
      g.fillStyle = bg
      g.beginPath()
      // roundRect não existe em navegadores mais antigos (Safari < 16, WebView antigo)
      if (g.roundRect) g.roundRect(x - w / 2, y, w, h, h / 2)
      else g.rect(x - w / 2, y, w, h)
      g.fill()
      g.fillStyle = '#fff'
      g.textAlign = 'center'
      g.textBaseline = 'middle'
      g.fillText(text, x, y + h / 2 + size * 0.04)
    }

    const frame = (now) => {
      raf = requestAnimationFrame(frame)
      try {
        draw(now)
      } catch (err) {
        // um quadro com erro não pode apagar a partida: registra uma vez e segue no próximo quadro
        if (!reported) {
          reported = true
          console.error('[campo 2D]', err)
        }
      }
    }

    const draw = (now) => {
      const dtReal = Math.min(0.05, (now - last) / 1000)
      last = now
      const d = director.current
      const I = imgs.current
      if (!d || !I) return
      const { paused: isPaused, speed: sp, orient: o } = live.current
      const { markers: mks, userSide: us } = view.current
      // 2x e 4x aceleram o campo na mesma proporção, em passos curtos (estável em qualquer velocidade)
      if (!isPaused) {
        let rest = dtReal * Math.max(1, Number(sp) || 1)
        while (rest > 1e-4) {
          const step = Math.min(rest, 1 / 60)
          d.update(step)
          rest -= step
        }
      }
      const st = d.state

      const cw = cv.width
      const ch = cv.height
      const R = fieldRect(cw, ch, o)
      g.setTransform(1, 0, 0, 1, 0, 0)
      g.clearRect(0, 0, cw, ch)
      g.drawImage(o === 'h' ? I.fieldH : I.fieldV, R.left, R.top, R.w, R.h)

      // tamanho mínimo legível no celular; acima disso, a escala real do kit
      const D = Math.max(PLAYER_D * R.m, 15 * dpr)
      const owner = st.ball.owner
      const b = st.ball

      // portador: anel amarelo no chão
      const op = owner ? st.players.find((p) => p.id === owner) : null
      if (op) {
        const [x, y] = R.at(op.x, op.y)
        const s = D * 1.65
        g.drawImage(I.possession, x - s / 2, y - s / 2, s, s)
      }

      // sombra da bola no ponto do campo
      if (!b.hidden) {
        const [x, y] = R.at(b.x, b.y)
        const s = Math.max(BALL_D * R.m * 1.8, 11 * dpr) * (1 + b.z * 0.08)
        g.globalAlpha = Math.max(0.25, 0.75 - b.z * 0.08)
        g.drawImage(I.shadow, x - s / 2, y - s / 4, s, s / 2)
        g.globalAlpha = 1
      }

      // atletas: um marcador por equipe, número pelo código
      const num = Math.round(D * 0.46)
      g.textAlign = 'center'
      g.textBaseline = 'middle'
      for (const p of st.players) {
        const [x, y] = R.at(p.x, p.y)
        const sd = p.side === 'a' ? 'a' : 'h'
        const mk = p.gk ? KEEPERS[sd] : mks[sd]
        const img = p.gk ? I[`gk_${sd}`] : I[mk.id]
        g.drawImage(img, x - D / 2, y - D / 2, D, D)
        if (p.number != null) {
          g.font = `800 ${num}px Inter, system-ui, sans-serif`
          g.fillStyle = mk.text
          g.fillText(String(p.number), x, y + num * 0.06)
        }
      }

      // bola: objeto separado, sobe na tela conforme a altura
      if (!b.hidden) {
        const [x, y] = R.at(b.x, b.y)
        const s = Math.max(BALL_D * R.m * 1.4, 10 * dpr) * (1 + b.z * 0.06)
        const lift = b.z * R.m * 0.9
        g.drawImage(I.ball, x - s / 2, y - lift - s / 2, s, s)
      }

      // nomes: quem tem a bola e quem comemora o gol
      const named = new Set()
      if (op) named.add(op)
      if (st.script?.phase === 'celebrate' && st.script.shooter) named.add(st.script.shooter)
      const fs = Math.max(9 * dpr, D * 0.42)
      for (const p of named) {
        const [x, y] = R.at(p.x, p.y)
        const label = p.name || ''
        if (!label) continue
        pill(label, x, y + D * 0.62, fs, p.side === us ? 'rgba(14,116,144,0.92)' : 'rgba(10,18,36,0.88)')
      }

      // o relógio espera o lance em andamento; o placar conta quando a bola entra
      const hold = d.holdMinute()
      if (hold !== lastHold) {
        lastHold = hold
        holdRef.current?.(hold)
      }
      const shown = d.takeRevealed()
      if (shown) revealRef.current?.(shown)
      const top = st.banners[0] || null
      const key = top ? top.id : null
      if (key !== lastBannerRef.current) {
        lastBannerRef.current = key
        setBanner(top ? { ...top } : null)
      }
    }
    raf = requestAnimationFrame(frame)
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
    }
  }, [ready])

  const flip = () =>
    setOrient((o) => {
      const n = o === 'h' ? 'v' : 'h'
      try {
        window.localStorage.setItem('sim.field2d', n)
      } catch {
        /* sem armazenamento: vale só nesta partida */
      }
      return n
    })

  const bannerText = (bn) => {
    const e = bn.ev
    if (!e) return bn.text || ''
    if (bn.kind === 'goal' || bn.kind === 'pen_goal') return `${e.player_name || ''} ${e.minute}'`
    if (bn.kind === 'sub') return `Entra ${e.player_name || ''}${e.player2_name ? ` · sai ${e.player2_name}` : ''}`
    if (bn.kind === 'foul') return bn.text || 'Falta'
    return `${BANNER_TEXT[bn.kind] ? `${BANNER_TEXT[bn.kind]} · ` : ''}${e.player_name || ''}`
  }

  return (
    <div className={`t2d is-${orient}`}>
      <div className="t2d-score">
        <span className="t2d-team h">
          <i style={{ background: markers.h.color }} />
          {clubs?.crest ? clubs.crest('h') : <ClubCrest clubId={data.home} size={18} />}
          <b>{home?.short || home?.name}</b>
        </span>
        <span className="t2d-result">
          <b>{score.h}</b>
          <em>×</em>
          <b>{score.a}</b>
        </span>
        <span className="t2d-team a">
          <b>{away?.short || away?.name}</b>
          {clubs?.crest ? clubs.crest('a') : <ClubCrest clubId={data.away} size={18} />}
          <i style={{ background: markers.a.color }} />
        </span>
        <span className={`t2d-clock ${finished ? 'is-done' : ''}`}>{clockLabel}</span>
        <button type="button" className="t2d-flip" onClick={flip} aria-label={orient === 'h' ? 'Campo na vertical' : 'Campo na horizontal'} title="Girar o campo">
          {orient === 'h' ? '↕' : '↔'}
        </button>
      </div>
      <div className="t2d-field" ref={wrap}>
        <canvas ref={canvas} className="t2d-canvas" aria-label="Partida vista de cima" role="img" />
        {!ready && !failed && <div className="t2d-loading">Preparando o campo…</div>}
        {failed && <div className="t2d-loading">Não foi possível carregar o campo. Os lances seguem no relato.</div>}
        {banner && (
          <div key={banner.id} className={`t2d-banner k-${banner.kind} ${banner.ev?.side && banner.ev.side === userSide ? 'is-mine' : ''}`}>
            {BANNER_ART[banner.kind] && <img src={BANNER_ART[banner.kind]} alt="" />}
            {banner.kind === 'text' ? <strong>{banner.text}</strong> : <span>{bannerText(banner)}</span>}
          </div>
        )}
      </div>
    </div>
  )
}
