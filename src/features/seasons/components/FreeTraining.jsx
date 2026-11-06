import { useEffect, useMemo, useRef, useState } from 'react'
import { Dumbbell, X, Zap } from 'lucide-react'
import { freeTraining } from '../../clubdev/clubDevApi'
import './free-training.css'

// TREINO LIVRE: sessão curta (3 exercícios) que aumenta o entrosamento com a formação sem jogar.
// Cada exercício é um minijogo de tempo: toque quando o marcador passar pela faixa verde.
// O aproveitamento (0–100%) vai ao servidor, que decide o ganho e cobra 1 energia.
const DRILLS = [
  { id: 'shape', label: 'Posicionamento', text: 'Os jogadores ocupam as vagas da formação.' },
  { id: 'build', label: 'Saída de bola', text: 'Triangulações do goleiro até o meio.' },
  { id: 'press', label: 'Pressão coordenada', text: 'O bloco sobe junto para roubar a bola.' },
]
const SPEED = [0.9, 1.15, 1.4] // voltas por segundo do marcador em cada exercício
const ZONE = [0.2, 0.16, 0.13] // largura da faixa verde

// posição "bagunçada" de cada vaga antes do treino (determinística para não pular a cada render)
const LOOSE = [[50, 50], [22, 30], [78, 34], [35, 70], [66, 66], [14, 56], [86, 58], [50, 22], [30, 46], [70, 48], [50, 82]]
const scatter = (i) => ({ x: LOOSE[i % LOOSE.length][0], y: LOOSE[i % LOOSE.length][1] })

export default function FreeTraining({ formation, value, energy, onClose, onDone }) {
  const [phase, setPhase] = useState('intro') // intro | drill | sending | done
  const [round, setRound] = useState(0)
  const [scores, setScores] = useState([])
  const [hit, setHit] = useState(null) // feedback do último toque
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const marker = useRef(null)
  const pos = useRef(0)
  const raf = useRef(0)
  const zoneStart = useMemo(() => 0.35 + ((round * 0.23) % 0.35), [round])

  // marcador indo e voltando (requestAnimationFrame, sem re-render por quadro)
  useEffect(() => {
    if (phase !== 'drill' || hit) return undefined
    let last = performance.now()
    const tick = (now) => {
      const dt = (now - last) / 1000
      last = now
      pos.current = (pos.current + dt * SPEED[round]) % 2
      const p = pos.current > 1 ? 2 - pos.current : pos.current
      if (marker.current) marker.current.style.left = `${p * 100}%`
      raf.current = requestAnimationFrame(tick)
    }
    raf.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf.current)
  }, [phase, round, hit])

  function tap() {
    if (phase !== 'drill' || hit) return
    const p = pos.current > 1 ? 2 - pos.current : pos.current
    const center = zoneStart + ZONE[round] / 2
    const dist = Math.abs(p - center)
    const score = dist <= ZONE[round] / 2 ? 1 - (dist / (ZONE[round] / 2)) * 0.25 : Math.max(0, 0.75 - (dist - ZONE[round] / 2) * 3)
    const next = [...scores, score]
    setScores(next)
    setHit(score >= 0.9 ? 'Perfeito!' : score >= 0.75 ? 'Muito bom' : score >= 0.4 ? 'Regular' : 'Errou o tempo')
    setTimeout(() => {
      setHit(null)
      pos.current = 0
      if (round < DRILLS.length - 1) setRound(round + 1)
      else finish(next)
    }, 900)
  }

  async function finish(all) {
    setPhase('sending')
    const quality = all.reduce((a, b) => a + b, 0) / all.length
    try {
      const r = await freeTraining(formation.id, Number(quality.toFixed(2)))
      setResult(r)
      setPhase('done')
      onDone?.(r)
    } catch (e) {
      setError(e.message)
      setPhase('intro')
      setRound(0)
      setScores([])
    }
  }

  const start = () => {
    setError('')
    setResult(null)
    setRound(0)
    setScores([])
    pos.current = 0
    setPhase('drill')
  }

  const slots = formation?.slots || []
  const organized = phase === 'done' || phase === 'sending' ? 1 : phase === 'drill' ? (round + (hit ? 1 : 0)) / DRILLS.length : 0
  const noEnergy = energy != null && energy <= 0
  const shown = result ? result.after : value

  return (
    <div className="ftr-overlay" role="dialog" aria-modal="true" aria-label={`Treino livre: ${formation?.name}`}>
      <div className="ftr">
        <header className="ftr-head">
          <span className="ftr-icon">
            <Dumbbell size={18} />
          </span>
          <div>
            <small>Treino livre</small>
            <b>{formation?.name}</b>
          </div>
          <button type="button" className="ftr-x" aria-label="Fechar" onClick={onClose} disabled={phase === 'sending'}>
            <X size={18} />
          </button>
        </header>

        <div className={`ftr-pitch ${phase === 'drill' ? `d-${DRILLS[round].id}` : ''}`} onClick={tap}>
          <svg viewBox="0 0 100 140" preserveAspectRatio="none" aria-hidden="true">
            <rect x="3" y="3" width="94" height="134" rx="1.5" />
            <line x1="3" y1="70" x2="97" y2="70" />
            <circle cx="50" cy="70" r="11" />
            <rect x="24" y="117" width="52" height="20" />
            <rect x="24" y="3" width="52" height="20" />
          </svg>
          {slots.map((s, i) => {
            const a = scatter(i)
            const x = a.x + (s.x - a.x) * organized
            const y = a.y + (s.y - a.y) * organized
            return (
              <i key={s.slot} className={`ftr-dot ${s.pos === 'GOL' ? 'is-gk' : ''}`} style={{ left: `${x}%`, top: `${y * 0.9 + 5}%`, transitionDelay: `${i * 30}ms` }}>
                <em>{s.pos}</em>
              </i>
            )
          })}
          {phase === 'drill' && <span className="ftr-ball" />}
          {hit && <strong className={`ftr-hit ${scores[scores.length - 1] >= 0.75 ? 'ok' : 'bad'}`}>{hit}</strong>}
        </div>

        <div className="ftr-fam">
          <small>Treinamento na formação</small>
          <i>
            <em className={shown >= 85 ? 'ok' : shown >= 65 ? 'mid' : 'low'} style={{ width: `${shown}%` }} />
            {result && <u style={{ left: `${result.before}%`, width: `${result.after - result.before}%` }} />}
          </i>
          <b>{shown}%</b>
        </div>

        {phase === 'intro' && (
          <>
            <ol className="ftr-drills">
              {DRILLS.map((d, i) => (
                <li key={d.id}>
                  <span>{i + 1}</span>
                  <div>
                    <b>{d.label}</b>
                    <small>{d.text}</small>
                  </div>
                </li>
              ))}
            </ol>
            <p className="ftr-note">Toque no campo quando o marcador passar pela faixa verde. Quanto melhor o tempo, maior o ganho de entrosamento.</p>
            {error && <p className="ftr-err">{error}</p>}
            <button type="button" className="gx-btn ftr-go" onClick={start} disabled={noEnergy || value >= 100}>
              {value >= 100 ? 'Formação dominada' : noEnergy ? 'Sem energia' : (
                <>
                  Começar treino · <Zap size={15} /> 1
                </>
              )}
            </button>
          </>
        )}

        {phase === 'drill' && (
          <div className="ftr-play">
            <div className="ftr-step">
              <small>
                Exercício {round + 1} de {DRILLS.length}
              </small>
              <b>{DRILLS[round].label}</b>
            </div>
            <div className="ftr-bar" onClick={tap}>
              <span className="ftr-zone" style={{ left: `${zoneStart * 100}%`, width: `${ZONE[round] * 100}%` }} />
              <span className="ftr-marker" ref={marker} />
            </div>
            <button type="button" className="gx-btn ftr-go" onClick={tap} disabled={Boolean(hit)}>
              Treinar!
            </button>
          </div>
        )}

        {phase === 'sending' && <p className="ftr-note ftr-center">Fechando a sessão…</p>}

        {phase === 'done' && result && (
          <div className="ftr-done">
            <p>
              Aproveitamento <b>{result.quality}%</b> · entrosamento <b>+{result.gain}</b>
            </p>
            <div className="ftr-actions">
              <button type="button" className="gx-btn-ghost" onClick={onClose}>
                Concluir
              </button>
              <button type="button" className="gx-btn" onClick={start} disabled={result.after >= 100 || (result.energy ?? 0) + (result.bonus_energy ?? 0) <= 0}>
                Treinar de novo · <Zap size={15} /> 1
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
