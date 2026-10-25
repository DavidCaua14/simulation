import { useState } from 'react'
import {
  MAX_PICKS, MAX_STAKE, MIN_STAKE, STAKE_CHIPS,
  formatMult, formatOdd, pickMultiplier, potentialCoins, potentialEnergy, potentialXp,
} from '../data/predictionRules'
import { placeTicket } from '../services/predictionsApi'
import { resultLabel } from '../utils/matchUtils'
import { Amount, CoinIcon, TicketIcon } from './PredIcons'

export function BetSlipBar({ count, multiplier, onOpen }) {
  if (count === 0) return null
  return (
    <button type="button" className="pred-slip-bar" onClick={onOpen}>
      <span className="pred-slip-count">{count}</span>
      <span><TicketIcon /> Ver bilhete</span>
      <strong>{formatMult(multiplier)}</strong>
    </button>
  )
}

export function BetSlipSheet({ slip, balance, onClose, onPlaced }) {
  const [stake, setStake] = useState(50)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const mult = slip.multiplier
  const maxStake = Math.min(MAX_STAKE, balance ?? 0)
  const valid = Number.isInteger(stake) && stake >= MIN_STAKE && stake <= MAX_STAKE && stake <= (balance ?? 0)
  const safeStake = Number.isInteger(stake) ? stake : 0

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
    <div className="sn-sheet-wrap" onClick={onClose}>
      <div className="sn-sheet pred-sheet" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <div className="pred-sheet-head">
          <h3 className="heading">Meu bilhete</h3>
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
              <b className="pred-slip-odd">{formatOdd(pickMultiplier(p))}</b>
              <button type="button" aria-label="Remover palpite" onClick={() => slip.remove(p.match.id)}>✕</button>
            </li>
          ))}
        </ul>

        <p className="pred-hint">
          Se <b>um</b> palpite errar, o bilhete inteiro é perdido. A odd total é a multiplicação das odds de cada
          palpite, e fica travada quando você confirma.
        </p>

        <h4 className="pred-section-title">
          Entrada
          <small className="pred-balance"><CoinIcon /> Saldo: {balance ?? '—'}</small>
        </h4>
        <div className="pred-chips">
          {STAKE_CHIPS.filter((v) => v <= (balance ?? 0)).map((v) => (
            <button key={v} type="button" className={`pred-chip ${stake === v ? 'is-on' : ''}`} onClick={() => setStake(v)}>
              {v}
            </button>
          ))}
          {maxStake >= MIN_STAKE && !STAKE_CHIPS.includes(maxStake) && (
            <button type="button" className={`pred-chip ${stake === maxStake ? 'is-on' : ''}`} onClick={() => setStake(maxStake)}>
              Máx.
            </button>
          )}
          <input
            className="pred-input"
            type="number"
            inputMode="numeric"
            min={MIN_STAKE}
            max={MAX_STAKE}
            aria-label="Valor da entrada"
            value={Number.isNaN(stake) ? '' : stake}
            onChange={(e) => setStake(parseInt(e.target.value, 10))}
          />
        </div>

        <div className="pred-summary">
          <div><span>Odd total</span><b>{formatMult(mult)}</b></div>
          <div className="pred-summary-big">
            <span>Retorno se acertar</span>
            <Amount kind="coin" value={potentialCoins(safeStake, mult)} />
          </div>
          <div><span>Você pode perder</span><Amount kind="coin" value={safeStake} sign="-" /></div>
          <div><span>Bônus de XP</span><b>+{potentialXp(safeStake, slip.count)} XP</b></div>
          <div><span>Bônus de energia</span><Amount kind="energy" value={potentialEnergy(slip.count)} sign="+" /></div>
        </div>

        {!valid && (
          <p className="pred-error">
            {stake > (balance ?? 0) ? 'Moedas insuficientes.' : `Entrada entre ${MIN_STAKE} e ${MAX_STAKE} moedas.`}
          </p>
        )}
        {error && <p className="pred-error">{error}</p>}

        <button type="button" className="gx-btn pred-cta" disabled={!valid || busy} onClick={confirm}>
          {busy ? 'Criando…' : `Confirmar bilhete · ${safeStake} moedas`}
        </button>
        <button type="button" className="gx-btn-ghost pred-cta" onClick={() => { slip.clear(); onClose() }}>
          Limpar bilhete
        </button>
      </div>
    </div>
  )
}
