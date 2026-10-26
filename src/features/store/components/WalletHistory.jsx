import { useEffect, useState } from 'react'
import { CircleAlert, Coins, Gem, Receipt, X, Zap } from 'lucide-react'
import { fetchWalletHistory } from '../services/storeApi'

// Extrato: cada entrada/saída da carteira com a origem (o servidor registra tudo em wallet_ledger).
const REASON = {
  opening_balance: 'Saldo inicial',
  shop_card: 'Compra na loja',
  wheel_spin: 'Giro da roleta',
  market_buy: 'Compra no mercado',
  market_sale: 'Venda no mercado',
  energy_pack: 'Pacote de energia',
  energy_exchange: 'Troca por energia',
  energy_regen: 'Recarga de energia',
  cosmetic: 'Item visual',
  event_reward: 'Recompensa de evento',
  daily_streak: 'Sequência diária',
  box_open: 'Caixa aberta',
  card_discard: 'Carta descartada',
  signing_bonus: 'Luvas de contrato',
  match_reward: 'Prêmio de partida',
  match_energy: 'Energia da partida',
  competition_prize: 'Premiação de competição',
  prediction_stake: 'Palpite feito',
  prediction_payout: 'Palpite premiado',
  manual_adjustment: 'Ajuste da administração',
  other: 'Outros',
}
const CUR = {
  coins: { Icon: Coins, cls: 'coins', unit: 'moedas' },
  diamonds: { Icon: Gem, cls: 'gems', unit: 'diamantes' },
  energy: { Icon: Zap, cls: 'energy', unit: 'energia' },
  bonus_energy: { Icon: Zap, cls: 'energy', unit: 'energia bônus' },
}

function detailText(e) {
  const d = e.detail
  if (!d) return null
  if (e.reason === 'market_buy') return `${d.card} · de ${d.other || 'jogador'}`
  if (e.reason === 'market_sale') return `${d.card} · para ${d.other || 'jogador'} (taxa descontada)`
  if (d.card) return d.card
  if (d.event) return d.event
  return null
}

export default function WalletHistory({ onClose }) {
  const [rows, setRows] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => {
    fetchWalletHistory(100).then(setRows).catch((e) => setError(e.message))
  }, [])

  return (
    <div className="cx-sheet-wrap" onClick={onClose} role="dialog" aria-modal="true" aria-label="Extrato">
      <div className="cx-sheet wh-sheet" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <h3><Receipt size={18} /> Extrato</h3>
        <p className="cx-hint">Últimas 100 movimentações de moedas, diamantes e energia.</p>
        {error && <p className="cx-error"><CircleAlert size={14} /> {error}</p>}
        {!rows && !error && <p className="cx-hint center">Carregando…</p>}
        {rows && rows.length === 0 && <p className="cx-hint center">Nenhuma movimentação ainda.</p>}
        {rows && rows.length > 0 && (
          <ul className="wh-list">
            {rows.map((e) => {
              const c = CUR[e.currency] || CUR.coins
              const det = detailText(e)
              return (
                <li key={e.id}>
                  <span className={`wh-ic ${c.cls}`}><c.Icon size={14} /></span>
                  <span className="wh-main">
                    <strong>{REASON[e.reason] || e.reason}</strong>
                    <small>{new Date(e.at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}{det ? ` · ${det}` : ''}</small>
                  </span>
                  <span className="wh-amt">
                    <b className={e.delta > 0 ? 'is-in' : 'is-out'}>{e.delta > 0 ? '+' : ''}{e.delta.toLocaleString('pt-BR')}</b>
                    <small>saldo {Number(e.balance).toLocaleString('pt-BR')} {c.unit}</small>
                  </span>
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </div>
  )
}
