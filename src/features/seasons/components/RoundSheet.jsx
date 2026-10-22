import { X } from 'lucide-react'
import RoundResults from './RoundResults'
import { buildRounds } from '../utils/seasonSelectors'
import { COMP_NAME } from '../utils/seasonUtils'

// Folha que sobe de baixo mostrando os "Jogos da rodada" de um jogo tocado no histórico.
// Usa só dados já carregados: abre na hora.
export default function RoundSheet({ target, byComp, myClub, onClose }) {
  const round = buildRounds(byComp[target.comp] || []).find((r) => r.key === `${target.stage}:${target.round_no}`)
  return (
    <div className="sn-sheet-wrap" onClick={onClose}>
      <div className="sn-sheet" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <header>
          <div>
            <small>{COMP_NAME[target.comp]}</small>
            <strong className="heading">{round?.label || 'Rodada'}</strong>
          </div>
          <button type="button" className="icon-btn" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="sn-sheet-body">{round ? <RoundResults matches={round.matches} myClub={myClub} /> : <p className="sn-muted">Rodada não encontrada.</p>}</div>
      </div>
    </div>
  )
}
