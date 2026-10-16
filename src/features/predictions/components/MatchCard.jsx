import { RESULT_MULTIPLIERS, formatMult } from '../data/predictionRules'
import { formatRound, formatTime } from '../utils/matchUtils'

const OPTIONS = [
  { id: 'home', label: 'Casa' },
  { id: 'draw', label: 'Empate' },
  { id: 'away', label: 'Fora' },
]

export function StatusBadge({ match }) {
  if (match.status === 'live') {
    return (
      <span className="pred-badge pred-badge-live">
        <i className="pred-dot" /> AO VIVO{match.minute ? ` · ${match.minute}'` : ''}
      </span>
    )
  }
  if (match.status === 'finished') return <span className="pred-badge">Encerrado</span>
  if (match.status === 'void') return <span className="pred-badge pred-badge-warn">Adiado / anulado</span>
  return <span className="pred-badge">{formatTime(match.kickoff_at)}</span>
}

function TeamRow({ name, logo, score, showScore }) {
  return (
    <div className="pred-team">
      <span className="pred-team-logo">{logo && <img src={logo} alt="" loading="lazy" />}</span>
      <span className="pred-team-name">{name}</span>
      {showScore && <strong className="pred-team-score">{score ?? 0}</strong>}
    </div>
  )
}

export default function MatchCard({ match, competitionName, pick, locked, onPickResult, onOpen }) {
  const showScore = match.status === 'live' || match.status === 'finished'

  return (
    <article className={`pred-card card ${match.status === 'live' ? 'is-live' : ''}`}>
      <div
        className="pred-card-main"
        role="button"
        tabIndex={0}
        onClick={() => onOpen(match.id)}
        onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && onOpen(match.id)}
      >
        <div className="pred-card-head">
          <span className="pred-comp">
            {competitionName}
            {match.round ? ` · ${formatRound(match.round)}` : ''}
          </span>
          <StatusBadge match={match} />
        </div>
        <TeamRow name={match.home_team} logo={match.home_logo} score={match.home_score} showScore={showScore} />
        <TeamRow name={match.away_team} logo={match.away_logo} score={match.away_score} showScore={showScore} />
      </div>

      {locked ? (
        <p className="pred-locked">
          {match.status === 'scheduled' ? 'Palpites encerrados' : 'Jogo já iniciado — palpites fechados'}
        </p>
      ) : (
        <div className="pred-picks">
          {OPTIONS.map((o) => (
            <button
              key={o.id}
              type="button"
              className={`pred-pick ${pick?.result === o.id ? 'is-on' : ''}`}
              onClick={() => onPickResult(match, o.id)}
            >
              <span>{o.label}</span>
              <small>{formatMult(RESULT_MULTIPLIERS[o.id])}</small>
            </button>
          ))}
        </div>
      )}

      {!locked && (
        <button type="button" className="pred-more" onClick={() => onOpen(match.id)}>
          {pick?.btts != null
            ? `Ambas marcam: ${pick.btts ? 'Sim' : 'Não'} · editar`
            : 'Detalhes · ambas as equipes marcam?'}
        </button>
      )}
    </article>
  )
}
