import { favoriteOf, formatOdd, resultOdd } from '../data/predictionRules'
import { formatCountdown, formatTime } from '../utils/matchUtils'
import { FavoriteIcon, TimerIcon } from './PredIcons'

const OPTIONS = [
  { id: 'home', label: 'Casa' },
  { id: 'draw', label: 'Empate' },
  { id: 'away', label: 'Fora' },
]

// eslint-disable-next-line no-unused-vars
export function StatusBadge({ match, now }) {
  // Sem cronômetro: do apito inicial até o resultado sair, o jogo fica só "Em andamento".
  if (match.status === 'live') {
    return <span className="pred-badge pred-badge-live"><i className="pred-dot" /> Em andamento</span>
  }
  if (match.status === 'finished') return <span className="pred-badge">Encerrado</span>
  if (match.status === 'void') return <span className="pred-badge pred-badge-warn">Adiado / anulado</span>
  return <span className="pred-badge">{formatTime(match.kickoff_at)}</span>
}

function Team({ name, logo, align }) {
  return (
    <span className={`pc-team ${align}`}>
      <span className="pc-logo">{logo ? <img src={logo} alt="" loading="lazy" /> : <i>{name?.[0]}</i>}</span>
      <b>{name}</b>
    </span>
  )
}

// Cartão do jogo no mesmo padrão "placar" do modo Temporadas: escudos frente a frente, odds embaixo.
export default function MatchCard({ match, now, pick, locked, onPickResult, onOpen }) {
  const showScore = (match.status === 'live' || match.status === 'finished') && match.home_score != null
  const fav = favoriteOf(match)
  const countdown = match.status === 'scheduled' && !locked ? formatCountdown(new Date(match.kickoff_at).getTime() - now) : null

  return (
    <article className={`pc ${match.status === 'live' ? 'is-live' : ''} ${pick ? 'has-pick' : ''}`}>
      <div
        className="pc-main"
        role="button"
        tabIndex={0}
        onClick={() => onOpen(match.id)}
        onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && onOpen(match.id)}
      >
        <div className="pc-head">
          <span className="pc-round">{match.round || ''}</span>
          <StatusBadge match={match} now={now} />
        </div>
        <div className="pc-versus">
          <Team name={match.home_team} logo={match.home_logo} align="home" />
          <span className={`pc-mid ${showScore ? 'is-score' : ''}`}>
            {showScore ? (
              <>
                {match.home_score}
                <i>:</i>
                {match.away_score}
              </>
            ) : (
              'VS'
            )}
          </span>
          <Team name={match.away_team} logo={match.away_logo} align="away" />
        </div>
        {countdown && (
          <span className="pc-count">
            <TimerIcon /> {countdown}
          </span>
        )}
        {match.status === 'live' && match.home_score == null && (
          <span className="pc-count">
            <TimerIcon /> O placar aparece quando o jogo terminar
          </span>
        )}
      </div>

      {locked ? (
        <p className="pred-locked">{match.status === 'scheduled' ? 'Palpites encerrados' : 'Jogo já iniciado: palpites fechados'}</p>
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
          {pick?.btts != null ? `Ambas marcam: ${pick.btts ? 'Sim' : 'Não'} · editar` : '+ Ambas as equipes marcam?'}
        </button>
      )}
    </article>
  )
}
