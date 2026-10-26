import { useEffect } from 'react'
import { Trophy } from 'lucide-react'

// Momento especial: recompensa conquistada (evento, sequência diária). É o único lugar fora da abertura de
// caixas com raios/brilho — o resto do app fica sóbrio. Os itens aparecem um a um.
// rewards: nós já renderizados (chips). actions: botões do rodapé.
export default function RewardReveal({ title = 'Recompensa conquistada!', subtitle, rewards = [], actions, onClose }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose?.()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="gx-reveal-wrap" role="dialog" aria-modal="true" aria-label={title} onClick={onClose}>
      <div className="gx-reveal" onClick={(e) => e.stopPropagation()}>
        <div className="gx-reveal-burst" aria-hidden="true" />
        <span className="gx-reveal-trophy" aria-hidden="true"><Trophy size={34} /></span>
        <small className="gx-reveal-kicker">{subtitle}</small>
        <h3>{title}</h3>
        <div className="gx-reveal-items">
          {rewards.map((node, i) => (
            <span key={i} className="gx-reveal-item" style={{ animationDelay: `${0.35 + i * 0.12}s` }}>{node}</span>
          ))}
        </div>
        <div className="gx-reveal-actions">{actions}</div>
      </div>
    </div>
  )
}
