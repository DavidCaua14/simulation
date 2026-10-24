import { Coins, Star, Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { POSITIONS } from '../../player/data/positions'
import useCountdown from '../hooks/useCountdown'
import { FREE_ENERGY, RECHARGE_HOURS, XP_PER_LEVEL, fmt, formatRemaining, popularityTier } from '../utils/seasonUtils'

// Destaque da carreira: clube (escudo e cores), atleta, nível com barra de XP e os recursos.
export default function CareerHero({ career, stats, season, onRecharged }) {
  const club = getClubById(career.club_id)
  const [c1, c2] = club?.colors || ['#1b3566', '#f5b800']
  const position = POSITIONS.find((p) => p.id === career.position)
  const xpPct = Math.max(0, Math.min(100, (career.xp / XP_PER_LEVEL) * 100))
  const pop = popularityTier(stats.popularity)
  const totalEnergy = career.energy + career.bonus_energy
  const remaining = useCountdown(career.next_reset_at, onRecharged)
  const full = career.energy >= FREE_ENERGY

  return (
    <section className="ch" style={{ '--c1': c1, '--c2': c2 }}>
      <span className="ch-stripes" aria-hidden="true" />
      <div className="ch-top">
        <span className="ch-crest">
          <ClubCrest clubId={career.club_id} size={64} />
        </span>
        <div className="ch-id">
          <small>Temporada {season.year}</small>
          <h2>{career.nickname}</h2>
          <span>
            {club?.name}
            {position ? ` · ${position.label}` : ''}
          </span>
        </div>
        <div className="ch-level" aria-label={`Nível ${career.level}`}>
          <small>NV</small>
          <b>{career.level}</b>
        </div>
      </div>

      <div className="ch-xp">
        <div className="gx-xp" role="progressbar" aria-valuemin={0} aria-valuemax={XP_PER_LEVEL} aria-valuenow={career.xp}>
          <i style={{ width: `${xpPct}%` }} />
        </div>
        <span>
          <b>{fmt(career.xp)}</b> / {fmt(XP_PER_LEVEL)} XP · faltam {fmt(XP_PER_LEVEL - career.xp)} para o nível {career.level + 1}
        </span>
      </div>

      <div className="ch-res">
        <div className="ch-tile coins" title="Moedas">
          <Coins size={16} />
          <b>{fmt(career.coins)}</b>
          <small>moedas</small>
        </div>
        <div className="ch-tile energy" title={`${FREE_ENERGY} energias a cada ${RECHARGE_HOURS}h. A energia bônus nunca zera.`}>
          <Zap size={16} fill="currentColor" />
          <b>{fmt(totalEnergy)}</b>
          <small>{full ? 'energia cheia' : remaining != null ? `recarga ${formatRemaining(remaining)}` : 'energia'}</small>
        </div>
        <div className="ch-tile fame" title="Popularidade: quanto maior, mais propostas de clubes">
          <Star size={16} fill="currentColor" />
          <b>{pop.label}</b>
          <small>fama {fmt(stats.popularity)}</small>
        </div>
      </div>
      {career.bonus_energy > 0 && <p className="ch-note">Inclui {career.bonus_energy} de energia bônus (não zera na recarga).</p>}
    </section>
  )
}
