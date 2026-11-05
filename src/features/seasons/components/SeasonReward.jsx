import { useState } from 'react'
import GameIcon from '../../../components/ui/GameIcon'
import { getClubById } from '../../club/data/clubs'
import { markSeasonRewardSeen } from '../services/managerApi'
import { fmt } from '../utils/seasonUtils'

// Fim de temporada: moedas por meta superada e título, e a reputação da temporada (com teto).
// O pagamento já foi feito no servidor, uma única vez; aqui só se mostra o resultado.
export default function SeasonReward({ reward, onClose }) {
  const [busy, setBusy] = useState(false)
  if (!reward) return null
  const d = reward.detail || {}
  const items = d.items || []
  const rep = Number(reward.reputation || 0)
  const close = async () => {
    setBusy(true)
    try {
      await markSeasonRewardSeen(reward.season_id)
    } catch {
      // segue: o aviso volta na próxima abertura
    }
    setBusy(false)
    onClose()
  }
  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label="Prêmio da temporada">
      <div className="sn-modal">
        <header className="sn-modal-head">
          <span>
            <small>Temporada {d.year ?? ''} · {getClubById(reward.club_id)?.name || ''}</small>
            <b>Prêmio da temporada</b>
          </span>
        </header>
        <ul className="sr-list">
          {items.map((it, i) => (
            <li key={i}>
              <span>
                {it.label}
                {it.kind === 'league' && it.pos != null ? ` · terminou em ${it.pos}º (meta ${it.target}º)` : ''}
              </span>
              <b><GameIcon name="coins" size={13} /> {fmt(it.coins)}</b>
            </li>
          ))}
          {d.titles > 0 && (
            <li>
              <span>{d.titles === 1 ? 'Título conquistado' : `${d.titles} títulos conquistados`}</span>
              <b><GameIcon name="coins" size={13} /> {fmt(d.title_coins ?? 0)}</b>
            </li>
          )}
          {items.length === 0 && !d.titles && <li><span>Nenhuma meta cumprida nesta temporada.</span></li>}
        </ul>
        <p className="sr-total">
          Total: <b><GameIcon name="coins" size={14} /> {fmt(reward.coins)}</b> · Reputação {rep >= 0 ? '+' : ''}{rep.toFixed(1)}
        </p>
        <div className="of-actions">
          <button type="button" className="gx-btn" onClick={close} disabled={busy}>
            {busy ? <span className="nm-spin" /> : null} Continuar
          </button>
        </div>
      </div>
    </div>
  )
}
