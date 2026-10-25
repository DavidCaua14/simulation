import { ChevronRight, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import CompEmblem from '../ui/CompEmblem'
import { EXPECTED_MATCHES } from '../utils/seasonSelectors'
import { COMP_NAME, COMP_THEME } from '../utils/seasonUtils'
import { compStatus } from '../utils/compStatus'

// Cartão de um campeonato (Início): identidade própria, situação, progresso e próximo objetivo.
export default function CompCard({ comp, onOpen }) {
  const t = COMP_THEME[comp.id] || { c1: '#2b3445', c2: '#c9d2e3', kicker: '' }
  const st = compStatus(comp)
  const inactive = comp.status === 'not_in' || comp.status === 'out'
  const pct = Math.min(100, (comp.played / (EXPECTED_MATCHES[comp.id] || comp.total || 1)) * 100)
  return (
    <button type="button" className={`cc status-${comp.status} ${inactive ? 'is-inactive' : ''}`} style={{ '--c1': t.c1, '--c2': t.c2 }} onClick={() => onOpen(comp.id)}>
      <span className="cc-emblem">
        <CompEmblem comp={comp.id} size={44} dim={inactive} />
      </span>
      <span className="cc-body">
        <small>{t.kicker}</small>
        <b>{COMP_NAME[comp.id]}</b>
        <span className="cc-line">{st.line}</span>
        {!inactive && comp.status !== 'finished' && (
          <span className="cc-bar" aria-label={`${comp.played} jogos disputados`}>
            <i style={{ width: `${pct}%` }} />
          </span>
        )}
        <span className="cc-goal">
          {comp.status === 'finished' && comp.champion ? (
            <>
              <Trophy size={12} /> Campeão: <ClubCrest clubId={comp.champion} size={14} />
            </>
          ) : (
            <>→ {st.goal}</>
          )}
        </span>
      </span>
      <ChevronRight size={18} className="cc-chev" />
    </button>
  )
}
