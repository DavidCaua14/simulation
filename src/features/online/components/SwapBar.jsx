import { ArrowLeftRight, X } from 'lucide-react'
import './pitch-card.css'

// Barra fixa da escalação (online e Temporadas): mostra quem foi tocado enquanto o técnico rola até o banco.
export default function SwapBar({ player, pos, onCancel }) {
  const name = player ? player.short_name || player.name || '' : null
  return (
    <div className="swap-bar" role="status" aria-live="polite">
      <ArrowLeftRight size={16} aria-hidden="true" />
      <span>
        <b>{name ? `Trocando: ${name}${pos || player?.position || player?.pos ? ` (${pos || player.position || player.pos})` : ''}` : 'Vaga selecionada'}</b>
        <small>Toque em outro jogador do campo ou do banco para trocar.</small>
      </span>
      <button type="button" onClick={onCancel} aria-label="Cancelar troca"><X size={16} /></button>
    </div>
  )
}
