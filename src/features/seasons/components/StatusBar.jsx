import { Coins, Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { FREE_ENERGY, XP_PER_LEVEL, fmt, formatRemaining } from '../utils/seasonUtils'

// Barra fixa no topo de TODAS as abas (como o HUD de um jogo): clube, nível/XP, moedas e energia.
export default function StatusBar({ career, season, remaining }) {
  const club = getClubById(career.club_id)
  const total = career.energy + career.bonus_energy
  const xpPct = Math.max(0, Math.min(100, (career.xp / XP_PER_LEVEL) * 100))
  const full = career.energy >= FREE_ENERGY

  return (
    <div className="sn-status">
      <div className="sn-status-main">
        <ClubCrest clubId={career.club_id} size={34} />
        <div className="sn-status-id">
          <b>{club?.name}</b>
          <small>
            {career.nickname} · Nível {career.level} · {season.year}
          </small>
        </div>
        <span className="sn-pill coins" title="Moedas">
          <Coins size={13} /> {fmt(career.coins)}
        </span>
        <span className="sn-pill energy" title="Energia: 1 por partida. A livre volta a 10 a cada 5h.">
          <Zap size={13} fill="currentColor" /> {fmt(total)}
        </span>
      </div>
      <div className="sn-status-xp" title={`${fmt(career.xp)} / ${fmt(XP_PER_LEVEL)} XP`}>
        <i style={{ width: `${xpPct}%` }} />
      </div>
      {!full && remaining != null && <small className="sn-status-timer">Energia: recarga em {formatRemaining(remaining)}</small>}
    </div>
  )
}
