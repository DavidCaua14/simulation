import { favoriteOf, formatOdd, resultOdd } from '../data/predictionRules'
import { estimateClock, formatCountdown, formatTime } from '../utils/matchUtils'
import { FavoriteIcon, TimerIcon } from './PredIcons'

const OPTIONS = [
  { id: 'home', label: 'Casa' },
  { id: 'draw', label: 'Empate' },
  { id: 'away', label: 'Fora' },
]

export function StatusBadge({ match, now }) {
  if (match.status === 'live') {
    // O plano gratuito da API não traz minuto: o relógio abaixo é uma ESTIMATIVA pelo horário de início.
    const clock = match.minute ? { phase: 'play', label: `${match.minute}'` } : estimateClock(match, now)
    if (clock?.phase === 'break') return <span className="pred-badge pred-badge-live" title="Tempo estimado"><i className="pred-dot" /> Intervalo</span>
    if (clock?.phase === 'wait') return <span className="pred-badge pred-badge-warn">Aguardando resultado</span>
    return (
      <span className="pred-badge pred-badge-live" title={match.minute ? undefined : 'Tempo estimado pelo horário de início'}>
        <i className="pred-dot" /> AO VIVO{clock ? ` · ${match.minute ? '' : '~'}${clock.label}` : ''}
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
      {showScore && score != null && <strong className="pred-team-score">{score}</strong>}
    </div>
  )
}

export default function MatchCard({ match, now, pick, locked, onPickResult, onOpen }) {
  const showScore = match.status === 'live' || match.status === 'finished'
  const fav = favoriteOf(match)
  const countdown = match.status === 'scheduled' && !locked ? formatCountdown(new Date(match.kickoff_at).getTime() - now) : null

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
          <span className="pred-comp">{match.round || ''}</span>
          <StatusBadge match={match} now={now} />
        </div>
        <TeamRow name={match.home_team} logo={match.home_logo} score={match.home_score} showScore={showScore} />
        <TeamRow name={match.away_team} logo={match.away_logo} score={match.away_score} showScore={showScore} />
        {countdown && (
          <span className="pred-countdown"><TimerIcon /> {countdown}</span>
        )}
        {match.status === 'live' && match.home_score == null && (
          <span className="pred-countdown"><TimerIcon /> Em andamento · placar na hora do apito final</span>
        )}
      </div>

      {locked ? (
        <p className="pred-locked">
          {match.status === 'scheduled' ? 'Palpites encerrados' : 'Jogo já iniciado: palpites fechados'}
        </p>
      ) : (
        <div className="pred-picks">
          {OPTIONS.map((o) => (
            <button
              key={o.id}
              type="button"
              className={`pred-pick ${pick?.result === o.id ? 'is-on' : ''}`}
              onClick={() => onPickResult(match, o.id)}
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
      )}

      {!locked && (
        <button type="button" className="pred-more" onClick={() => onOpen(match.id)}>
          {pick?.btts != null
            ? `Ambas marcam: ${pick.btts ? 'Sim' : 'Não'} · editar`
            : 'Mais opções · ambas as equipes marcam?'}
        </button>
      )}
    </article>
  )
}
