import { useState } from 'react'
import { Gavel, X } from 'lucide-react'
import OnlineCrest from './OnlineCrest'
import { OvrBadge, PlayerFace } from './PlayerFut'
import { money } from '../onlineUtils'

// Resultado dos leilões que o técnico disputou: aparece para o vencedor e para quem perdeu.
export default function AuctionResults({ results, onSeen }) {
  const [i, setI] = useState(0)
  const r = results[i]
  if (!r) return null
  const d = r.data || {}
  const next = () => (i + 1 < results.length ? setI(i + 1) : onSeen(results.map((x) => x.id)))
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label="Leilão encerrado">
      <div className={`on-result ${d.won ? 'is-won' : 'is-lost'}`}>
        <button type="button" className="on-result-x" onClick={() => onSeen(results.map((x) => x.id))} aria-label="Fechar"><X size={16} /></button>
        <small><Gavel size={13} /> Leilão encerrado{results.length > 1 ? ` · ${i + 1}/${results.length}` : ''}</small>
        <h3>{d.won ? 'Contratado!' : 'Você perdeu a disputa'}</h3>
        <div className="on-result-player">
          <PlayerFace seed={d.player?.name} colors={d.winner?.colors} size={84} />
          {d.player && <OvrBadge p={d.player} />}
          <strong>{d.player?.name}</strong>
        </div>
        <div className="on-result-winner">
          <OnlineCrest club={d.winner} size={34} />
          <span><small>Vencedor</small><b>{d.winner?.name}</b></span>
          <em>{money(d.price)}</em>
        </div>
        <button type="button" className="gx-btn" onClick={next}>{i + 1 < results.length ? 'Próximo' : 'Continuar'}</button>
      </div>
    </div>
  )
}
