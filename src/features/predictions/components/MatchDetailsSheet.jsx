import { BTTS_MULTIPLIER, RESULT_MULTIPLIERS, formatMult, pickMultiplier } from '../data/predictionRules'
import { formatDateTime, formatRound } from '../utils/matchUtils'
import { StatusBadge } from './MatchCard'

export default function MatchDetailsSheet({ match, competitionName, pick, locked, onResult, onBtts, onClose }) {
  const showScore = match.status === 'live' || match.status === 'finished'
  const mult = pick ? pickMultiplier(pick) : null

  const results = [
    { id: 'home', label: match.home_team },
    { id: 'draw', label: 'Empate' },
    { id: 'away', label: match.away_team },
  ]

  return (
    <div className="pred-overlay" onClick={onClose}>
      <div className="pred-sheet" onClick={(e) => e.stopPropagation()}>
        <span className="pred-grabber" />
        <div className="pred-sheet-head">
          <span className="pred-comp">
            {competitionName}
            {match.round ? ` · ${formatRound(match.round)}` : ''}
          </span>
          <StatusBadge match={match} />
        </div>

        <div className="pred-versus">
          <div>
            <span className="pred-team-logo big">{match.home_logo && <img src={match.home_logo} alt="" />}</span>
            <strong>{match.home_team}</strong>
          </div>
          <div className="pred-versus-score">
            {showScore ? `${match.home_score ?? 0} x ${match.away_score ?? 0}` : 'x'}
            <small>{formatDateTime(match.kickoff_at)}</small>
          </div>
          <div>
            <span className="pred-team-logo big">{match.away_logo && <img src={match.away_logo} alt="" />}</span>
            <strong>{match.away_team}</strong>
          </div>
        </div>

        {locked ? (
          <p className="pred-locked">Os palpites deste jogo estão fechados.</p>
        ) : (
          <>
            <h4 className="pred-section-title">Quem vence?</h4>
            <div className="pred-picks">
              {results.map((o) => (
                <button
                  key={o.id}
                  type="button"
                  className={`pred-pick ${pick?.result === o.id ? 'is-on' : ''}`}
                  onClick={() => onResult(match, o.id)}
                >
                  <span>{o.label}</span>
                  <small>{formatMult(RESULT_MULTIPLIERS[o.id])}</small>
                </button>
              ))}
            </div>

            <h4 className="pred-section-title">As duas equipes vão marcar?</h4>
            <div className="pred-picks two">
              {[
                { v: true, label: 'Sim, ambas marcam' },
                { v: false, label: 'Não, alguém fica sem marcar' },
              ].map((o) => (
                <button
                  key={String(o.v)}
                  type="button"
                  className={`pred-pick ${pick?.btts === o.v ? 'is-on' : ''}`}
                  onClick={() => onBtts(match, o.v)}
                >
                  <span>{o.label}</span>
                  <small>{formatMult(BTTS_MULTIPLIER)}</small>
                </button>
              ))}
            </div>

            <p className="pred-hint">
              Se você marcar resultado <b>e</b> "ambas marcam", precisa acertar os dois. Toque de novo
              numa opção para desmarcar.
            </p>
            {mult && <p className="pred-total">Multiplicador deste jogo: <b>{formatMult(mult)}</b></p>}
          </>
        )}

        <button type="button" className="pred-btn" onClick={onClose}>Fechar</button>
      </div>
    </div>
  )
}
