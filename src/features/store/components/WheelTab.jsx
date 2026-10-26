import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CircleAlert, Gem, ShieldCheck, X } from 'lucide-react'
import CardView from '../../cards/components/CardView'
import { tierOf } from '../../cards/data/tiers'
import { fetchWheel, newRequestId, spinWheel } from '../services/storeApi'
import { cardFacts } from './cardFacts'
import { useAudio } from '../../audio/AudioContext'
import { Skeleton } from '../../../components/ui/feedback'

const SPIN_MS = 4200
const reduceMotion = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

// fatias proporcionais à chance REAL (a roda não engana: 3% ocupa 3% da volta)
function layout(segments) {
  let a = 0
  return segments.map((s) => {
    const sweep = (Number(s.probability) / 100) * 360
    const seg = { ...s, a0: a, a1: a + sweep }
    a += sweep
    return seg
  })
}
function arcPath(a0, a1, r = 100) {
  const p = (deg) => {
    const rad = ((deg - 90) * Math.PI) / 180
    return [r + r * Math.cos(rad), r + r * Math.sin(rad)]
  }
  const [x0, y0] = p(a0)
  const [x1, y1] = p(a1)
  return `M${r},${r} L${x0},${y0} A${r},${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1},${y1} Z`
}

function bandLabel(s) {
  if (s.min_overall && s.max_overall) return ` · nota ${s.min_overall}–${s.max_overall}`
  if (s.max_overall) return ` · nota até ${s.max_overall}`
  if (s.min_overall) return ` · nota ${s.min_overall}+`
  return ''
}

function Wheel({ segs, rotation, spinning }) {
  return (
    <div className="wh-wrap">
      <span className="wh-pointer" aria-hidden="true" />
      <svg viewBox="0 0 200 200" className={`wh-wheel ${spinning ? 'is-spinning' : ''}`} style={{ transform: `rotate(${rotation}deg)`, transitionDuration: spinning ? `${SPIN_MS}ms` : '0ms' }} aria-hidden="true">
        {segs.map((s) => (
          <path key={s.id} d={arcPath(s.a0, s.a1)} fill={s.color} stroke="rgba(0,0,0,.35)" strokeWidth="0.6" />
        ))}
        {segs.filter((s) => s.a1 - s.a0 >= 24).map((s) => {
          const mid = (s.a0 + s.a1) / 2
          return (
            <text key={s.id} x="100" y="30" transform={`rotate(${mid} 100 100)`} textAnchor="middle" className="wh-label">
              {Number(s.probability).toLocaleString('pt-BR')}%
            </text>
          )
        })}
        <circle cx="100" cy="100" r="17" className="wh-hub" />
      </svg>
      <span className="wh-hub-gem" aria-hidden="true"><Gem size={18} /></span>
    </div>
  )
}

// Roleta: 10 diamantes por giro, só Lendas e Épicas. Chances e garantia aparecem ANTES de girar.
export default function WheelTab({ onSpent, onOpenCollection }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [rotation, setRotation] = useState(0)
  const [spinning, setSpinning] = useState(false)
  const [result, setResult] = useState(null)
  const { playSfx } = useAudio()
  const requestRef = useRef(null) // reaproveitado se a chamada falhar (tentar de novo não cobra duas vezes)

  const load = useCallback(async () => {
    try {
      setData(await fetchWheel())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])

  const segs = useMemo(() => layout(data?.segments || []), [data])
  const cost = data?.cost ?? 10
  const diamonds = data?.diamonds ?? 0
  const short = diamonds < cost
  const pity = data?.pity

  async function spin() {
    if (spinning || short) return
    setError('')
    if (!requestRef.current) requestRef.current = newRequestId()
    let r
    try {
      r = await spinWheel(requestRef.current)
    } catch (e) {
      setError(e.message) // mesmo id na próxima tentativa
      return
    }
    requestRef.current = null
    onSpent?.()
    const seg = segs.find((s) => s.id === r.segment)
    // ponto de parada dentro da fatia sorteada (longe da borda), levado até o ponteiro no topo
    const target = seg ? seg.a0 + (seg.a1 - seg.a0) * (0.25 + Math.random() * 0.5) : 0
    const base = rotation + 360 * 5
    const next = base + ((((-target - base) % 360) + 360) % 360)
    if (reduceMotion()) {
      setRotation(next)
      playSfx(r.tier === 'epica' ? 'levelup' : 'reward')
      setResult(r)
      load()
      return
    }
    setSpinning(true)
    setRotation(next)
    setTimeout(() => {
      setSpinning(false)
      playSfx(r.tier === 'epica' ? 'levelup' : 'reward')
      setResult(r)
      load()
    }, SPIN_MS + 150)
  }

  if (!data && !error) return <Skeleton rows={2} variant="tall" />

  return (
    <section className="wh" aria-label="Roleta de cartas">
      {data && (
        <>
          <Wheel segs={segs} rotation={rotation} spinning={spinning} />

          <button type="button" className="gx-btn wh-spin" disabled={spinning || short || !data.active} onClick={spin}>
            {spinning ? 'Girando…' : <>Girar · <Gem size={16} /> {cost}</>}
          </button>
          <p className="wh-balance">
            Você tem <b><Gem size={13} /> {diamonds}</b>
            {short && <> · faltam {cost - diamonds} diamantes para girar</>}
          </p>
          {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}

          <div className="wh-odds" role="table" aria-label="Chances de cada prêmio">
            <div className="wh-odds-head" role="row">
              <span role="columnheader">Prêmio</span><span role="columnheader">Chance</span>
            </div>
            {segs.map((s) => (
              <div key={s.id} className="wh-odds-row" role="row">
                <span role="cell"><i style={{ background: s.color }} /> {s.label}
                  <small>{bandLabel(s)} · {s.cards} cartas</small>
                </span>
                <b role="cell">{Number(s.probability).toLocaleString('pt-BR')}%</b>
              </div>
            ))}
            <p className="wh-odds-sum">Total: {Number(data.probability_sum).toLocaleString('pt-BR')}% · sorteio feito no servidor</p>
          </div>

          {pity?.enabled && (
            <div className="wh-pity">
              <ShieldCheck size={18} />
              <p>
                <b>Garantia de {pity.segment_label}:</b> se você girar {pity.threshold} vezes seguidas sem tirar uma {pity.segment_label}, o{' '}
                {pity.threshold}º giro é {pity.segment_label} garantida. O contador volta a zero sempre que sair uma.
                <br />
                <span className="wh-pity-now">
                  {pity.remaining === 1 ? 'O próximo giro é Épica garantida!' : `Faltam no máximo ${pity.remaining} giros para a garantia.`}
                </span>
              </p>
            </div>
          )}

          {data.history?.length > 0 && (
            <div className="wh-hist">
              <h4>Seus últimos giros</h4>
              <ul>
                {data.history.map((h) => (
                  <li key={h.id} style={{ '--tier': tierOf(h.card.tier).color }}>
                    <b>{h.card.overall}</b> {h.card.name}
                    <small>{tierOf(h.card.tier).label}{h.pity ? ' · garantia' : ''}</small>
                  </li>
                ))}
              </ul>
            </div>
          )}
          <p className="cx-hint sh-foot">Cartas repetidas entram na coleção como cópia extra (podem ser descartadas por moedas/diamantes).</p>
        </>
      )}

      {result && (
        <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Resultado do giro" onClick={() => setResult(null)}>
          <div className={`cx-sheet sh-confirm wh-result t-${result.tier}`} onClick={(e) => e.stopPropagation()}>
            <button type="button" className="cx-sheet-x" onClick={() => setResult(null)} aria-label="Fechar"><X size={18} /></button>
            <p className="wh-result-kicker" style={{ color: tierOf(result.tier).color }}>{result.tier === 'epica' ? 'ÉPICA!' : result.segment_label}</p>
            <CardView card={result.card} width={170} shine />
            <h3>{result.card.name}</h3>
            <p className="sh-item-facts">
              Nota <b>{result.card.overall}</b> · {cardFacts(result.card).position} · {cardFacts(result.card).club}
            </p>
            <p className="sh-msg is-ok">{result.new ? 'Carta nova na sua coleção!' : `Repetida: agora você tem ${result.qty} cópias.`}</p>
            {result.pity && <p className="cx-hint">Esta veio pela garantia.</p>}
            <div className="sh-confirm-actions">
              <button type="button" className="gx-btn-ghost" onClick={onOpenCollection}>Ver coleção</button>
              <button type="button" className="gx-btn" onClick={() => setResult(null)}>Continuar</button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}
