import { useState } from 'react'
import { Gift } from 'lucide-react'
import BoxOpener from './BoxOpener'
import { tierOf } from '../data/tiers'

// Aviso da Home quando chegam caixas novas (boas-vindas ou diária).
// "Abrir agora" já abre aqui mesmo; "Depois" deixa tudo na caixa de entrada.
export default function DailyRewardsModal({ granted, boxes, onOpened, onDone }) {
  const [opening, setOpening] = useState(false)
  // as mais novas; da mais comum para a mais rara (a melhor fica por último, para dar emoção)
  const fresh = boxes.slice(-granted.granted).sort((a, b) => tierOf(a.tier).rank - tierOf(b.tier).rank)
  const welcome = granted.welcome > 0

  if (opening) {
    return <BoxOpener boxes={fresh} onClose={onDone} onOpened={onOpened} />
  }

  return (
    <div className="bx-overlay bx-gift" role="dialog" aria-modal="true" aria-label="Caixas novas">
      <div className="bx-bg" />
      <div className="bx-gift-card">
        <span className="bx-gift-icon">
          <Gift size={26} />
        </span>
        <h2>{welcome ? 'Bem-vindo ao jogo!' : 'Suas caixas de hoje chegaram!'}</h2>
        <p>
          {welcome ? 'Você ganhou ' : 'Você recebeu '}
          <b>
            {granted.granted} caixa{granted.granted === 1 ? '' : 's'}
          </b>
          . Elas ficam guardadas na caixa de entrada.
        </p>
        <div className="bx-gift-boxes">
          {fresh.map((b, i) => (
            <img key={b.id} src={tierOf(b.tier).closed} alt={`Caixa ${tierOf(b.tier).label}`} style={{ '--i': i }} draggable="false" />
          ))}
        </div>
        <div className="bx-actions">
          <button type="button" className="bx-btn ghost" onClick={onDone}>
            Depois
          </button>
          <button type="button" className="bx-btn" onClick={() => setOpening(true)}>
            Abrir agora
          </button>
        </div>
      </div>
    </div>
  )
}
