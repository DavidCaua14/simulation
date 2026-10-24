import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Coins, Gem, X, Zap } from 'lucide-react'
import CardView from './CardView'
import { isRare, sourceLabel, tierOf } from '../data/tiers'
import { openBox } from '../services/cardsApi'

const SPARKS = 18
const SHAKE_MS = 800 // duração mínima da "tremida" da caixa (a resposta do banco chega junto)

// Faíscas: direção e distância calculadas uma vez (não mudam a cada render).
function makeSparks() {
  return Array.from({ length: SPARKS }, (_, i) => {
    const ang = (i / SPARKS) * Math.PI * 2 + (i % 2) * 0.17
    const dist = 90 + ((i * 37) % 70)
    return { dx: Math.cos(ang) * dist, dy: Math.sin(ang) * dist - 20, d: (i % 6) * 30, s: 0.6 + ((i * 13) % 10) / 14 }
  })
}

const buzz = (pattern) => {
  try {
    navigator.vibrate?.(pattern)
  } catch {
    /* sem vibração */
  }
}

/**
 * Abertura de caixas, em 3 toques:   (1) caixa fechada, "toque para abrir"
 *                                    (2) caixa abre (e o prêmio já é sorteado no banco)
 *                                    (3) "toque para ver" -> prêmios + carta
 * boxes   : [{ id, tier, source }]  — abre na ordem; ao terminar uma, aparece "Próxima caixa".
 * onOpened: (resultado) => void     — chamado a cada caixa aberta (para atualizar carteira/lista).
 * onClose : (resultados[]) => void  — ao fechar a tela.
 */
export default function BoxOpener({ boxes, onOpened, onClose }) {
  const [idx, setIdx] = useState(0)
  const [phase, setPhase] = useState('idle') // idle | opening | ready | reveal | error
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const results = useRef([])
  const sparks = useMemo(makeSparks, [])
  const box = boxes[idx]
  const t = tierOf(box?.tier)
  const rare = isRare(box?.tier)
  const last = idx >= boxes.length - 1

  const close = useCallback(() => onClose?.(results.current), [onClose])

  const doOpen = useCallback(async () => {
    if (!box || phase !== 'idle') return
    setPhase('opening')
    setError('')
    buzz(15)
    try {
      const [r] = await Promise.all([openBox(box.id), new Promise((res) => setTimeout(res, SHAKE_MS))])
      results.current = [...results.current, r]
      setResult(r)
      onOpened?.(r)
      setPhase('ready')
      buzz(rare ? [30, 40, 30] : 25)
    } catch (e) {
      setError(e.message || 'Não foi possível abrir a caixa.')
      setPhase('error')
    }
  }, [box, phase, rare, onOpened])

  const onStage = () => {
    if (phase === 'idle') doOpen()
    else if (phase === 'ready') {
      setPhase('reveal')
      if (isRare(result?.card?.tier)) buzz([40, 60, 40, 60, 80])
    }
  }

  const next = () => {
    setResult(null)
    setPhase('idle')
    setIdx((i) => i + 1)
  }

  // Esc fecha (menos no meio do sorteio)
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && phase !== 'opening' && (phase === 'ready' ? setPhase('reveal') : close())
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [phase, close])

  if (!box) return null
  const card = result?.card
  const cardTier = tierOf(card?.tier)
  const showBox = phase !== 'reveal'
  const hint =
    phase === 'idle' ? 'Toque para abrir' : phase === 'opening' ? 'Abrindo…' : phase === 'ready' ? 'Toque para ver os prêmios' : ''

  return (
    <div className={`bx-overlay ${rare ? 'is-rare' : ''}`} data-phase={phase} style={{ '--tier': t.color, '--glow': t.glow }} role="dialog" aria-modal="true" aria-label="Abrir caixa">
      <div className="bx-bg" />
      <div className="bx-rays" aria-hidden="true" />

      <header className="bx-top">
        <div className="bx-title">
          <b style={{ color: t.color }}>Caixa {t.label}</b>
          <small>
            {sourceLabel(box.source)}
            {boxes.length > 1 ? ` · ${idx + 1} de ${boxes.length}` : ''}
          </small>
        </div>
        {phase !== 'opening' && (
          <button type="button" className="bx-x" onClick={phase === 'ready' ? () => setPhase('reveal') : close} aria-label={phase === 'ready' ? 'Ver prêmios' : 'Fechar'}>
            <X size={20} />
          </button>
        )}
      </header>

      {showBox && (
        <button type="button" className="bx-stage" onClick={onStage} disabled={phase === 'opening' || phase === 'error'} aria-label={hint || 'Caixa'}>
          <span className="bx-halo" aria-hidden="true" />
          <span className="bx-box" aria-hidden="true">
            <img className="bx-img closed" src={t.closed} alt="" draggable="false" />
            <img className="bx-img open" src={t.open} alt="" draggable="false" />
          </span>
          <span className="bx-flash" aria-hidden="true" />
          {(phase === 'ready' || phase === 'opening') && (
            <span className="bx-sparks" aria-hidden="true">
              {sparks.map((s, i) => (
                <i key={i} style={{ '--dx': `${s.dx}px`, '--dy': `${s.dy}px`, '--d': `${s.d}ms`, '--s': s.s }} />
              ))}
            </span>
          )}
        </button>
      )}

      {phase === 'reveal' && result && (
        <section className="bx-prizes" aria-live="polite">
          {card ? (
            <div className="bx-card-wrap" style={{ '--tier': cardTier.color, '--glow': cardTier.glow }}>
              <span className="bx-card-aura" aria-hidden="true" />
              <CardView card={card} width={210} shine className="bx-card" />
              <span className={`bx-badge ${result.card_new ? 'is-new' : ''}`}>{result.card_new ? 'NOVA!' : `Repetida · x${result.card_qty}`}</span>
            </div>
          ) : (
            <p className="bx-nocard">Nenhuma carta disponível nesta caixa ainda.</p>
          )}

          <div className="bx-chips">
            <span className="bx-chip coins" style={{ '--i': 0 }}>
              <Coins size={16} /> +{result.coins}
            </span>
            {result.energy > 0 && (
              <span className="bx-chip energy" style={{ '--i': 1 }}>
                <Zap size={16} fill="currentColor" /> +{result.energy}
              </span>
            )}
            {result.diamonds > 0 && (
              <span className="bx-chip gems" style={{ '--i': 2 }}>
                <Gem size={16} /> +{result.diamonds}
              </span>
            )}
          </div>

          {card && !result.card_new && <p className="bx-dup">Repetidas podem ser descartadas por moedas e diamantes na sua coleção.</p>}
        </section>
      )}

      <footer className="bx-bottom">
        {hint && <p className={`bx-hint ${phase}`}>{hint}</p>}

        {phase === 'error' && (
          <div className="bx-error">
            <p>{error}</p>
            <div className="bx-actions">
              <button type="button" className="bx-btn ghost" onClick={close}>
                Fechar
              </button>
              <button type="button" className="bx-btn" onClick={() => setPhase('idle')}>
                Tentar de novo
              </button>
            </div>
          </div>
        )}

        {phase === 'reveal' && (
          <div className="bx-actions">
            {last ? (
              <button type="button" className="bx-btn" onClick={close}>
                Concluir
              </button>
            ) : (
              <>
                <button type="button" className="bx-btn ghost" onClick={close}>
                  Guardar o resto
                </button>
                <button type="button" className="bx-btn" onClick={next}>
                  Próxima ({boxes.length - idx - 1})
                </button>
              </>
            )}
          </div>
        )}
      </footer>
    </div>
  )
}
