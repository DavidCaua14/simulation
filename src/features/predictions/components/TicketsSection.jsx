import { useCallback, useEffect, useState } from 'react'
import { fetchMyStats, fetchTickets } from '../services/predictionsApi'
import { formatMult } from '../data/predictionRules'
import { formatDateTime, resultLabel, withLiveStatus } from '../utils/matchUtils'
import { useNow } from '../hooks/useMatches'
import { Amount, PickStatusIcon } from './PredIcons'

const STATUS = {
  pending: { label: 'Em andamento', cls: 'pending' },
  won: { label: 'Ganhou', cls: 'won' },
  lost: { label: 'Perdeu', cls: 'lost' },
  void: { label: 'Anulado', cls: 'void' },
}

function Ticket({ t, now }) {
  const st = STATUS[t.status]
  return (
    <article className="pred-ticket card">
      <div className="pred-ticket-head">
        <span className={`pred-pill ${st.cls}`}>{st.label}</span>
        <small>{formatDateTime(t.created_at)}</small>
      </div>

      <ul className="pred-ticket-picks">
        {t.ticket_picks.map((p) => {
          const m = withLiveStatus(p.matches, now)
          return (
            <li key={p.id}>
              <PickStatusIcon status={p.status} />
              <div>
                <strong>{m.home_team} x {m.away_team}</strong>
                <small>
                  {p.pick_result && resultLabel(p.pick_result, m)}
                  {p.pick_result && p.pick_btts != null && ' · '}
                  {p.pick_btts != null && `Ambas marcam: ${p.pick_btts ? 'Sim' : 'Não'}`}
                  {' · odd '}{formatMult(Number(p.multiplier))}
                </small>
              </div>
              <em>
                {m.status === 'scheduled'
                  ? formatDateTime(m.kickoff_at)
                  : m.home_score == null
                    ? m.status === 'live' ? 'Em andamento' : '—'
                    : `${m.home_score}–${m.away_score}`}
              </em>
            </li>
          )
        })}
      </ul>

      <div className="pred-ticket-foot">
        <span>Entrada <Amount kind="coin" value={t.stake} /> · odd {formatMult(Number(t.multiplier))}</span>
        {t.status === 'pending' && <span>Retorno possível <Amount kind="coin" value={t.potential_coins} /></span>}
        {t.status === 'won' && (
          <span className="won">
            <Amount kind="coin" value={t.reward_coins} sign="+" /> · +{t.reward_xp} XP · <Amount kind="energy" value={t.reward_energy} sign="+" />
          </span>
        )}
        {t.status === 'lost' && <span className="lost"><Amount kind="coin" value={t.stake} sign="-" /></span>}
        {t.status === 'void' && <span>Moedas devolvidas</span>}
      </div>
    </article>
  )
}

export default function TicketsSection({ onWalletChange }) {
  const now = useNow(15000)
  const [tickets, setTickets] = useState([])
  const [stats, setStats] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('open')

  const load = useCallback(async () => {
    try {
      const [list, mine] = await Promise.all([fetchTickets(), fetchMyStats().catch(() => null)])
      setTickets(list)
      setStats(mine)
      setError('')
      onWalletChange()
    } catch {
      setError('Não foi possível carregar seus bilhetes.')
    } finally {
      setLoading(false)
    }
  }, [onWalletChange])

  useEffect(() => {
    load()
    const id = setInterval(load, 20000)
    return () => clearInterval(id)
  }, [load])

  const list = tickets.filter((t) => (tab === 'open' ? t.status === 'pending' : t.status !== 'pending'))
  const settled = (stats?.tickets_won ?? 0) + (stats?.tickets_lost ?? 0)

  return (
    <>
      {stats && settled > 0 && (
        <div className="pred-stats">
          <div><b>{stats.tickets_won}</b><small>ganhos</small></div>
          <div><b>{stats.tickets_lost}</b><small>perdidos</small></div>
          <div><b>{Math.round((stats.tickets_won / settled) * 100)}%</b><small>acerto</small></div>
          <div><b>{formatMult(Number(stats.best_multiplier))}</b><small>maior odd</small></div>
        </div>
      )}
      <div className="pred-seg small">
        <button type="button" className={tab === 'open' ? 'is-on' : ''} onClick={() => setTab('open')}>Abertos</button>
        <button type="button" className={tab === 'done' ? 'is-on' : ''} onClick={() => setTab('done')}>Finalizados</button>
      </div>
      <div className="pred-list">
        {loading && <p className="pred-empty">Carregando…</p>}
        {!loading && error && <p className="pred-empty">{error}</p>}
        {!loading && !error && list.length === 0 && (
          <p className="pred-empty">
            {tab === 'open' ? 'Você não tem bilhetes em andamento. Escolha seus palpites na aba Jogos.' : 'Nenhum bilhete finalizado ainda.'}
          </p>
        )}
        {list.map((t) => <Ticket key={t.id} t={t} now={now} />)}
      </div>
    </>
  )
}
