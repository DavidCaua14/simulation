import { Coins, Star, Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { POSITIONS } from '../../player/data/positions'
import useCountdown from '../hooks/useCountdown'
import { FREE_ENERGY, RECHARGE_HOURS, XP_PER_LEVEL, fmt, formatRemaining, popularityTier } from '../utils/seasonUtils'

// "Ficha" do jogador no topo: clube, nível, barra de XP, moedas, energia e popularidade.
export default function PlayerCard({ career, stats, season, onRecharged }) {
  const club = getClubById(career.club_id)
  const position = POSITIONS.find((p) => p.id === career.position)
  const xpPct = Math.max(0, Math.min(100, (career.xp / XP_PER_LEVEL) * 100))
  const pop = popularityTier(stats.popularity)
  const totalEnergy = career.energy + career.bonus_energy
  const remaining = useCountdown(career.next_reset_at, onRecharged)
  const full = career.energy >= FREE_ENERGY

  return (
    <section className="sn-hero card">
      <div className="sn-hero-top">
        <span className="sn-crest-wrap">
          <ClubCrest clubId={career.club_id} size={56} />
        </span>
        <div className="sn-hero-id">
          <small>Temporada {season.year}</small>
          <strong className="heading">{career.nickname}</strong>
          <span>
            {club?.name}
            {position ? ` · ${position.label}` : ''}
          </span>
        </div>
        <div className="sn-level" aria-label={`Nível ${career.level}`}>
          <b>{career.level}</b>
          <small>NÍVEL</small>
        </div>
      </div>

      <div className="sn-xp" role="progressbar" aria-valuemin={0} aria-valuemax={XP_PER_LEVEL} aria-valuenow={career.xp}>
        <i style={{ width: `${xpPct}%` }} />
        <span>
          {fmt(career.xp)} / {fmt(XP_PER_LEVEL)} XP
        </span>
      </div>

      <div className="sn-chips">
        <div className="sn-chip coins" title="Moedas">
          <Coins size={15} />
          <b>{fmt(career.coins)}</b>
        </div>
        <div className="sn-chip energy" title={`${FREE_ENERGY} energias a cada ${RECHARGE_HOURS}h. A energia comprada nunca zera.`}>
          <Zap size={15} fill="currentColor" />
          <b>{fmt(totalEnergy)}</b>
          <small>{full ? 'cheia' : remaining != null ? `recarga ${formatRemaining(remaining)}` : ''}</small>
        </div>
        <div className="sn-chip fame" title="Popularidade: quanto maior, mais propostas de clubes">
          <Star size={15} fill="currentColor" />
          <b>{pop.label}</b>
          <small>{fmt(stats.popularity)}</small>
        </div>
      </div>

      {career.bonus_energy > 0 && <p className="sn-hint">Inclui {career.bonus_energy} de energia bônus (não zera na recarga).</p>}
    </section>
  )
}
