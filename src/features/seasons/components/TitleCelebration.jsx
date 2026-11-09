import { useEffect, useMemo } from 'react'
import { PartyPopper, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { play } from '../../audio/sfx'
import CompEmblem from '../ui/CompEmblem'
import { COMPETITIONS, COMP_NAME } from '../utils/seasonUtils'
import { markTitleSeen } from '../utils/titleParty'
import './title-celebration.css'

// Título conquistado: tela de festa uma vez por competição e temporada (ver utils/titleParty.js).
const COLORS = ['#ffd257', '#ffffff', '#f5b800', '#7be38a', '#5aa9ff', '#ff6b7f']

export default function TitleCelebration({ title, hub, account, onClose }) {
  const club = getClubById(hub.coach.club_id)
  const clinched = title.kind === 'clinched'
  const confetti = useMemo(
    () =>
      Array.from({ length: 48 }, (_, i) => ({
        left: (i * 37) % 100,
        delay: ((i * 13) % 30) / 10,
        dur: 2.6 + ((i * 7) % 20) / 10,
        color: COLORS[i % COLORS.length],
        rot: (i * 47) % 360,
      })),
    [],
  )

  useEffect(() => {
    play('goal_for')
    const t = setTimeout(() => play('reward'), 900)
    return () => clearTimeout(t)
  }, [])

  const close = () => {
    markTitleSeen(account, hub.season.id, title.competition)
    onClose()
  }

  return (
    <div className="ttc" role="dialog" aria-modal="true" aria-label="Título conquistado">
      <div className="ttc-confetti" aria-hidden="true">
        {confetti.map((c, i) => (
          <i key={i} style={{ left: `${c.left}%`, background: c.color, animationDelay: `${c.delay}s`, animationDuration: `${c.dur}s`, transform: `rotate(${c.rot}deg)` }} />
        ))}
      </div>
      <div className="ttc-card" style={{ '--ttc-c1': club?.colors?.[0] || '#1d6b2f', '--ttc-c2': club?.colors?.[1] || '#ffd257' }}>
        <div className="ttc-rays" aria-hidden="true" />
        <span className="ttc-kicker">
          <PartyPopper size={16} /> {clinched ? 'Campeão matematicamente!' : 'Título conquistado!'}
        </span>
        <div className="ttc-badges">
          <ClubCrest clubId={hub.coach.club_id} size={84} />
          <Trophy className="ttc-trophy" size={58} strokeWidth={1.6} />
          <CompEmblem comp={title.competition} size={64} />
        </div>
        <h2>CAMPEÃO!</h2>
        <p className="ttc-comp">{COMP_NAME[title.competition] || COMPETITIONS[title.competition]?.name || title.competition}</p>
        <p className="ttc-msg">
          Parabéns, {club?.name || 'equipe'}! {clinched ? 'Nenhum rival alcança mais o seu time: a taça já é sua, mesmo com rodadas por jogar.' : 'Elenco, comissão técnica e torcida fazem a festa. Temporada para entrar na história.'}
        </p>
        <button type="button" className="gx-btn ttc-btn" onClick={close}>
          Comemorar
        </button>
      </div>
    </div>
  )
}
