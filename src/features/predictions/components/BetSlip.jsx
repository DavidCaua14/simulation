import { useState } from 'react'
import {
  MAX_PICKS, MAX_STAKE, MIN_STAKE, STAKE_CHIPS,
  formatMult, potentialCoins, potentialEnergy, potentialXp,
} from '../data/predictionRules'
import { placeTicket } from '../services/predictionsApi'
import { resultLabel } from '../utils/matchUtils'

export function BetSlipBar({ count, multiplier, onOpen }) {
  if (count === 0) return null
  return (
    <button type="button" className="pred-slip-bar" onClick={onOpen}>
      <span className="pred-slip-count">{count}</span>
      <span>Meu bilhete</span>
      <strong>{formatMult(multiplier)}</strong>
    </button>
  )
}

export function BetSlipSheet({ slip, balance, onClose, onPlaced }) {
  const [stake, setStake] = useState(50)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const mult = slip.multiplier
  const valid = Number.isInteger(stake) && stake >= MIN_STAKE && stake <= MAX_STAKE && stake <= (balance ?? 0)

  async function confirm() {
    if (!valid || busy) return
    setBusy(true)
    setError('')
    try {
      await placeTicket(stake, slip.pickList)
      slip.clear()
      onPlaced()
    } catch (e) {
      setError(e.message || 'Não foi possível criar o bilhete.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="pred-overlay" onClick={onClose}>
      <div className="pred-sheet" onClick={(e) => e.stopPropagation()}>
        <span className="pred-grabber" />
        <div className="pred-sheet-head">
          <h3>Meu bilhete</h3>
          <span className="pred-comp">{slip.count}/{MAX_PICKS} jogos</span>
        </div>

        <ul className="pred-slip-list">
          {slip.pickList.map((p) => (
            <li key={p.match.id}>
              <div>
                <strong>{p.match.home_team} x {p.match.away_team}</strong>
                {p.result && <span>{resultLabel(p.result, p.match)}</span>}
                {p.btts != null && <span>Ambas marcam: {p.btts ? 'Sim' : 'Não'}</span>}
              </div>
              <button type="button" aria-label="Remover" onClick={() => slip.remove(p.match.id)}>✕</button>
            </li>
          ))}
        </ul>

        <p className="pred-hint">
          Atenção: se <b>um</b> palpite errar, o bilhete inteiro é perdido. Quanto mais jogos, maior o prêmio.
        </p>

        <h4 className="pred-section-title">Quanto apostar? <small>Saldo: 🪙 {balance ?? '—'}</small></h4>
        <div className="pred-chips">
          {STAKE_CHIPS.map((v) => (
            <button key={v} type="button" className={`pred-chip ${stake === v ? 'is-on' : ''}`} onClick={() => setStake(v)}>
              {v}
            </button>
          ))}
          <input
            className="pred-input"
            type="number"
            inputMode="numeric"
            min={MIN_STAKE}
            max={MAX_STAKE}
            value={Number.isNaN(stake) ? '' : stake}
            onChange={(e) => setStake(parseInt(e.target.value, 10))}
          />
        </div>

        <div className="pred-summary">
          <div><span>Multiplicador</span><b>{formatMult(mult)}</b></div>
          <div><span>Se ganhar: moedas</span><b>🪙 {potentialCoins(stake || 0, mult)}</b></div>
          <div><span>Se ganhar: XP</span><b>+{potentialXp(stake || 0, mult)} XP</b></div>
          <div><span>Se ganhar: energia</span><b>⚡ +{potentialEnergy(slip.count)}</b></div>
        </div>

        {!valid && (
          <p className="pred-error">
            {stake > (balance ?? 0) ? 'Moedas insuficientes.' : `Valor entre ${MIN_STAKE} e ${MAX_STAKE} moedas.`}
          </p>
        )}
        {error && <p className="pred-error">{error}</p>}

        <button type="button" className="pred-btn primary" disabled={!valid || busy} onClick={confirm}>
          {busy ? 'Criando…' : `Confirmar bilhete · 🪙 ${stake || 0}`}
        </button>
        <button type="button" className="pred-btn" onClick={() => { slip.clear(); onClose() }}>
          Limpar bilhete
        </button>
      </div>
    </div>
  )
}
