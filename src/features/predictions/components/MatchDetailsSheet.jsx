import { bttsOdd, favoriteOf, formatMult, formatOdd, pickMultiplier, resultOdd } from '../data/predictionRules'
import { formatDateTime, formatRound } from '../utils/matchUtils'
import { StatusBadge } from './MatchCard'
import { FavoriteIcon } from './PredIcons'

export default function MatchDetailsSheet({ match, competitionName, now, pick, locked, onResult, onBtts, onClose }) {
  const showScore = (match.status === 'live' || match.status === 'finished') && match.home_score != null
  const mult = pick ? pickMultiplier({ ...pick, match }) : null
  const fav = favoriteOf(match)

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
          <StatusBadge match={match} now={now} />
        </div>

        <div className="pred-versus">
          <div>
            <span className="pred-team-logo big">{match.home_logo && <img src={match.home_logo} alt="" />}</span>
            <strong>{match.home_team}</strong>
          </div>
          <div className="pred-versus-score">
            {showScore ? `${match.home_score} x ${match.away_score}` : 'x'}
            <small>{match.status === 'live' ? 'Em andamento' : formatDateTime(match.kickoff_at)}</small>
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
                  aria-pressed={pick?.result === o.id}
                >
                  <span>
                    {o.label}
                    {fav === o.id && <FavoriteIcon className="pred-fav" aria-label="Favorito" />}
                  </span>
                  <b>{formatOdd(resultOdd(match, o.id))}</b>
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
                  aria-pressed={pick?.btts === o.v}
                >
                  <span>{o.label}</span>
                  <b>{formatOdd(bttsOdd(match, o.v))}</b>
                </button>
              ))}
            </div>

            <p className="pred-hint">
              A odd é o quanto sua entrada multiplica se você acertar. Favoritos pagam menos, azarões pagam mais.
              Se marcar resultado <b>e</b> "ambas marcam", precisa acertar os dois. Toque de novo numa opção para
              desmarcar.
            </p>
            {mult && mult !== 1 && <p className="pred-total">Odd deste jogo no seu bilhete: <b>{formatMult(mult)}</b></p>}
          </>
        )}

        <button type="button" className="pred-btn" onClick={onClose}>Fechar</button>
      </div>
    </div>
  )
}
