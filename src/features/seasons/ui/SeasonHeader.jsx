import { ChevronLeft, Coins, Zap } from 'lucide-react'
import { FREE_ENERGY, XP_PER_LEVEL, fmt, formatRemaining } from '../utils/seasonUtils'

// Cabeçalho único do modo Temporadas: voltar discreto, título esportivo e recursos (energia/moedas).
// A borda de baixo é a barra de XP do nível atual. Sem botão de tema (fica no Perfil).
export default function SeasonHeader({ title, career, season, remaining, onBack, backLabel = 'Voltar ao menu' }) {
  const xpPct = career ? Math.max(0, Math.min(100, (career.xp / XP_PER_LEVEL) * 100)) : 0
  const energy = career ? career.energy + career.bonus_energy : null
  const recharging = career && career.energy < FREE_ENERGY && remaining != null

  return (
    <header className="sh">
      <button type="button" className="sh-back" onClick={onBack} aria-label={backLabel}>
        <ChevronLeft size={20} strokeWidth={2.6} />
      </button>

      <div className="sh-title">
        <small>
          Temporadas{season ? ` ${season.year}` : ''}
          {career ? <b> · NV {career.level}</b> : null}
        </small>
        <h1>{title}</h1>
      </div>

      {career && (
        <div className="sh-res">
          <span className="sh-pill energy" title={`Energia: 1 por partida. A livre volta a ${FREE_ENERGY} a cada 5h.`}>
            <Zap size={13} fill="currentColor" />
            <b>{fmt(energy)}</b>
            {recharging && <small>{formatRemaining(remaining)}</small>}
          </span>
          <span className="sh-pill coins" title="Moedas">
            <Coins size={13} />
            <b>{fmt(career.coins)}</b>
          </span>
        </div>
      )}

      <span className="sh-xp" role="progressbar" aria-label="Experiência do nível" aria-valuemin={0} aria-valuemax={XP_PER_LEVEL} aria-valuenow={career?.xp ?? 0}>
        <i style={{ width: `${xpPct}%` }} />
      </span>
    </header>
  )
}
