import { useState } from 'react'
import { Delete, X } from 'lucide-react'
import { CLUB_MONEY_SCALE, clubMoney } from '../utils/clubMoney'
import './keypad.css'

const UNITS = { mil: 1e3, mi: 1e6 }

// TECLADO DE OFERTA (CM17): digita o valor em R$ mil ou R$ mi, LIMPAR e CONFIRMAR.
// O valor devolvido está na unidade do banco (clubMoney: R$ 1.000 por unidade).
export default function MoneyKeypad({ title, subtitle, info = [], label = 'Sua oferta', initial = 0, confirmText = 'Confirmar', busy = false, error = null, extra = null, onConfirm, onClose }) {
  const reais0 = Number(initial || 0) * CLUB_MONEY_SCALE
  const [unit, setUnit] = useState(reais0 >= 1e6 ? 'mi' : 'mil')
  const [text, setText] = useState(reais0 ? String(+(reais0 / UNITS[reais0 >= 1e6 ? 'mi' : 'mil']).toFixed(2)) : '')
  const reais = Math.round(Number(text || 0) * UNITS[unit])
  const units = Math.round(reais / CLUB_MONEY_SCALE)

  const press = (k) => {
    if (k === ',' && (text.includes('.') || !text)) return
    setText((t) => (t.length >= 9 ? t : (t === '0' && k !== ',' ? '' : t) + (k === ',' ? '.' : k)))
  }
  const switchUnit = (u) => {
    if (u === unit) return
    const value = Number(text || 0) * UNITS[unit]
    setUnit(u)
    setText(value ? String(+(value / UNITS[u]).toFixed(u === 'mi' ? 2 : 0)) : '')
  }

  return (
    <div className="kp-overlay" role="dialog" aria-modal="true" aria-label={title}>
      <section className="kp">
        <header>
          <b>{title}</b>
          <button type="button" className="kp-x" aria-label="Fechar" onClick={onClose} disabled={busy}>
            <X size={18} />
          </button>
        </header>
        {subtitle && <h3>{subtitle}</h3>}
        {info.length > 0 && (
          <dl className="kp-info">
            {info.map(([k, v]) => (
              <div key={k}>
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
        )}
        {extra}
        <div className="kp-value">
          <small>{label}</small>
          <b>{clubMoney(units)}</b>
        </div>
        <div className="kp-units" role="radiogroup" aria-label="Unidade">
          {Object.keys(UNITS).map((u) => (
            <button key={u} type="button" role="radio" aria-checked={unit === u} className={unit === u ? 'is-on' : ''} onClick={() => switchUnit(u)}>
              R$ {u}
            </button>
          ))}
        </div>
        <div className="kp-keys">
          {['7', '8', '9', '4', '5', '6', '1', '2', '3', ',', '0'].map((k) => (
            <button key={k} type="button" onClick={() => press(k)}>
              {k}
            </button>
          ))}
          <button type="button" aria-label="Apagar" onClick={() => setText((t) => t.slice(0, -1))}>
            <Delete size={20} />
          </button>
        </div>
        {error && <p className="kp-error" role="alert">{error}</p>}
        <div className="kp-actions">
          <button type="button" className="kp-clear" onClick={() => setText('')} disabled={busy}>
            Limpar
          </button>
          <button type="button" className="gx-btn" onClick={() => onConfirm(units)} disabled={busy || units <= 0}>
            {busy ? 'Enviando…' : confirmText}
          </button>
        </div>
      </section>
    </div>
  )
}
