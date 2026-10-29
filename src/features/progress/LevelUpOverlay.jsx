import { useEffect, useState } from 'react'
import GameIcon from '../../components/ui/GameIcon'
import { useAudio } from '../audio/AudioContext'
import './level-up.css'

// Animação de NOVO NÍVEL (qualquer tela). Fecha sozinha ou com um toque.
export default function LevelUpOverlay() {
  const { playSfx } = useAudio()
  const [ev, setEv] = useState(null)
  useEffect(() => {
    const on = (e) => setEv({ ...e.detail, key: Date.now() })
    window.addEventListener('game:levelup', on)
    return () => window.removeEventListener('game:levelup', on)
  }, [])
  useEffect(() => {
    if (!ev) return undefined
    playSfx?.('levelup')
    const t = setTimeout(() => setEv(null), 4200)
    return () => clearTimeout(t)
  }, [ev, playSfx])
  if (!ev) return null
  return (
    <div className="lvl-ov" role="alert" aria-live="assertive" key={ev.key} onClick={() => setEv(null)}>
      <LevelBurst from={ev.from} to={ev.to} />
      <p className="lvl-tap">Toque para continuar</p>
    </div>
  )
}

// Medalhão do nível com raios, brilho e confete (também usado na tela de novidades).
export function LevelBurst({ from, to, compact = false }) {
  return (
    <div className={`lvl-burst ${compact ? 'is-compact' : ''}`}>
      <span className="lvl-rays" aria-hidden="true" />
      <span className="lvl-confetti" aria-hidden="true">
        {Array.from({ length: 14 }, (_, i) => <i key={i} style={{ '--i': i }} />)}
      </span>
      <small className="lvl-kicker">
        <GameIcon name="highlight" size={18} /> Subiu de nível!
      </small>
      <span className="lvl-medal">
        {from != null && from !== to && <em className="lvl-from">{from}</em>}
        <b className="lvl-to">{to}</b>
      </span>
      <strong className="lvl-label">Nível {to}</strong>
    </div>
  )
}
