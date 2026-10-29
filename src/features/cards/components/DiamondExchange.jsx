import GameIcon from '../../../components/ui/GameIcon'
import { useState } from 'react'
import { X } from 'lucide-react'
import { DIAMOND_TO_ENERGY } from '../data/tiers'
import { exchangeDiamonds } from '../services/cardsApi'

// Troca de diamantes por energia (a energia "bônus", que nunca é zerada).
export default function DiamondExchange({ diamonds, onClose, onDone }) {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState('')
  const options = [1, 5, 10].filter((n) => n <= Math.max(diamonds, 1))
  if (diamonds > 10) options.push(diamonds)

  async function swap(n) {
    setBusy(true)
    setMsg('')
    try {
      const r = await exchangeDiamonds(n)
      setMsg(`Pronto! +${r.energy_gained} de energia.`)
      await onDone?.()
    } catch (e) {
      setMsg(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label="Trocar diamantes" onClick={onClose}>
      <div className="cx-sheet" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} aria-label="Fechar">
          <X size={18} />
        </button>
        <h3>Trocar diamantes por energia</h3>
        <p className="cx-meta">
          1 <GameIcon name="diamond" size={13} /> = {DIAMOND_TO_ENERGY} <GameIcon name="energy" size={13} /> · você tem <b>{diamonds}</b>
        </p>
        <div className="cx-swap">
          {options.map((n) => (
            <button key={n} type="button" className="bx-btn ghost" disabled={busy || diamonds < n} onClick={() => swap(n)}>
              {n === diamonds && n > 10 ? 'Todos' : n} <GameIcon name="diamond" size={14} /> → +{n * DIAMOND_TO_ENERGY} <GameIcon name="energy" size={14} />
            </button>
          ))}
        </div>
        {diamonds < 1 && <p className="cx-hint">Você ainda não tem diamantes. Você pode conquistá-los nos eventos.</p>}
        {msg && <p className="cx-msg">{msg}</p>}
        <p className="cx-hint">A energia bônus permanece disponível após a recarga diária.</p>
      </div>
    </div>
  )
}
