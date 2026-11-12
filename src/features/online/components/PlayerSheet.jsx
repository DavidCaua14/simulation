import { useState } from 'react'
import { FileSignature, Gavel, TrendingUp, UserMinus, X } from 'lucide-react'
import { POS_NAME } from '../../seasons/utils/managerUtils'
import { FutCard } from './PlayerFut'
import { money } from '../onlineUtils'

const AUCTION_STEPS = [[0.5, 'Mínimo'], [0.75, '75%'], [1, 'Valor'], [1.5, '+50%'], [2, 'Dobro']]
const round100 = (n) => Math.ceil(n / 100) * 100
// salário pela nota (mesma fórmula de on_wage no banco)
const wageFor = (ovr, age) => Math.ceil((Math.max(1, ovr - 45) ** 2 * 0.65 + Math.max(0, ovr - 75) ** 2 * 12) * (age < 24 ? 1.1 : age >= 31 ? 0.9 : 1))

// FICHA DO JOGADOR do elenco: carta, nota atual e até onde pode chegar, contrato e as ações (leiloar, dispensar, renovar).
export default function PlayerSheet({ p, club, seasonId, busy, listed, onClose, onSell, onRenew, onAuction }) {
  const [mode, setMode] = useState(null)
  const [step, setStep] = useState(1)
  const left = (p.contract_end ?? 0) - (seasonId || 0)
  const ovr = Math.round(p.ovr)
  const pot = Math.max(ovr, Math.round(p.pot ?? p.ovr))
  const room = pot - ovr
  const startPrice = step === 0.5 ? Math.max(500, Math.round(p.value * 0.5)) : round100(p.value * step)
  const positions = [p.pos, ...(p.sec || [])].map((x) => POS_NAME[x] || x).join(' · ')
  return (
    <div className="on-modal on-ps" role="dialog" aria-modal="true" aria-label={p.name} onClick={onClose}>
      <div className="on-ps-card gx-panel" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <div className="on-ps-top">
          <FutCard p={p} club={club} size="sm" />
          <div className="on-ps-id">
            <h3>{p.name}</h3>
            <small>{positions}</small>
            <small>{p.age} anos{p.nat ? ` · ${p.nat}` : ''}{p.number != null ? ` · camisa ${p.number}` : ''}</small>
            {listed && <span className="on-ps-tag"><Gavel size={12} /> Em leilão</span>}
          </div>
        </div>
        <div className="on-ps-grow">
          <span><small>Nota atual</small><b>{ovr}</b></span>
          <i aria-hidden="true"><TrendingUp size={18} /></i>
          <span className="is-pot"><small>Pode chegar a</small><b>{pot}</b></span>
          <em>{room > 0 ? `+${room} de evolução` : 'No auge'}</em>
          <span className="on-ps-bar" role="progressbar" aria-valuemin={40} aria-valuemax={99} aria-valuenow={ovr}>
            <i className="is-pot" style={{ width: `${Math.min(100, ((pot - 40) / 59) * 100)}%` }} />
            <i style={{ width: `${Math.min(100, ((ovr - 40) / 59) * 100)}%` }} />
          </span>
        </div>
        <dl className="on-ps-stats">
          <div><dt>Valor</dt><dd>{money(p.value)}</dd></div>
          <div><dt>Salário</dt><dd>{money(p.wage)}/dia</dd></div>
          <div><dt>Contrato</dt><dd>{left <= 0 ? 'Último ano' : `+${left} temp.`}</dd></div>
          <div><dt>Condição</dt><dd>{Math.round(p.cond)}%</dd></div>
        </dl>

        {!mode && (
          <div className="on-ps-actions">
            <button type="button" className="gx-btn" disabled={busy || listed} onClick={() => setMode('auction')}><Gavel size={15} /> Leiloar</button>
            <button type="button" className="gx-btn-ghost" disabled={busy || left >= 3} onClick={() => setMode('renew')}><FileSignature size={15} /> Renovar</button>
            <button type="button" className="gx-btn-ghost" disabled={busy || listed} onClick={() => setMode('sell')}><UserMinus size={15} /> Dispensar</button>
          </div>
        )}
        {mode === 'auction' && (
          <div className="on-ps-step">
            <small>Lance inicial · 1 hora no mercado</small>
            <div className="on-auc-steps" role="group" aria-label="Lance inicial">
              {AUCTION_STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
            </div>
            <button type="button" className="gx-btn" disabled={busy} onClick={() => onAuction(p, startPrice)}><Gavel size={15} /> Leiloar por {money(startPrice)}</button>
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
        {mode === 'sell' && (
          <div className="on-ps-step">
            <small>Ele deixa o clube agora e volta ao mercado</small>
            <button type="button" className="gx-btn" disabled={busy} onClick={() => onSell(p)}><UserMinus size={15} /> Dispensar · +{money(p.sell ?? Math.round(p.value * 0.6))}</button>
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
        {mode === 'renew' && (
          <div className="on-ps-step">
            <small>Salário {money(p.wage)} → {money(wageFor(p.ovr, p.age))}/dia</small>
            {[1, 2, 3].filter((y) => left + y <= 3).map((y) => (
              <button key={y} type="button" className="gx-btn-ghost" disabled={busy} onClick={() => onRenew(p, y)}>
                +{y} temporada{y > 1 ? 's' : ''} · luva {money(wageFor(p.ovr, p.age) * 8 * y)}
              </button>
            ))}
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
      </div>
    </div>
  )
}
