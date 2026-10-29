import GameIcon from '../../../components/ui/GameIcon'
import { ChevronLeft } from 'lucide-react'
import { FREE_ENERGY, XP_PER_LEVEL, fmt, formatRemaining, seasonLabel } from '../utils/seasonUtils'

// Cabeçalho padrão dos modos de jogo (Temporadas, Palpites): voltar discreto, título esportivo e recursos (energia/moedas).
// A borda de baixo é a barra de XP do nível atual. Sem botão de tema (fica no Perfil).
export default function SeasonHeader({ title, career, season, remaining, onBack, backLabel = 'Voltar ao menu', kicker }) {
  const xpPct = career ? Math.max(0, Math.min(100, (career.xp / XP_PER_LEVEL) * 100)) : 0
  const energy = career && career.energy != null ? career.energy + (career.bonus_energy ?? 0) : null
  const recharging = career && career.energy < FREE_ENERGY && remaining != null

  return (
    <header className="sh">
      {onBack && (
        <button type="button" className="sh-back" onClick={onBack} aria-label={backLabel} title={backLabel}>
          <ChevronLeft size={20} strokeWidth={2.6} />
        </button>
      )}

      <div className="sh-title">
        <small>
          {kicker ?? (season ? `Temporada ${seasonLabel(season.year, season.region)}` : 'Carreira')}
          {!kicker && season?.status === 'active' && season.day_no != null ? ` · dia ${season.day_no}` : ''}
          {career ? <b> · NV {career.level}</b> : null}
        </small>
        <h1>{title}</h1>
      </div>

      {career && (
        <div className="sh-res">
          <span className="sh-pill energy" title={`Energia: 1 por partida. A livre volta a ${FREE_ENERGY} a cada 5h.`}>
            <GameIcon name="energy" size={13} />
            <b>{fmt(energy)}</b>
            {recharging && <small>{formatRemaining(remaining)}</small>}
          </span>
          <span className="sh-pill coins" title="Moedas">
            <GameIcon name="coins" size={13} />
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
