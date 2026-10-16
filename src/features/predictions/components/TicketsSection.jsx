import { useCallback, useEffect, useState } from 'react'
import { fetchTickets } from '../services/predictionsApi'
import { formatMult } from '../data/predictionRules'
import { formatDateTime, resultLabel } from '../utils/matchUtils'

const STATUS = {
  pending: { label: 'Em andamento', cls: 'pending' },
  won: { label: 'Ganhou', cls: 'won' },
  lost: { label: 'Perdeu', cls: 'lost' },
  void: { label: 'Anulado', cls: 'void' },
}
const PICK_ICON = { pending: '⏳', won: '✅', lost: '❌', void: '↩️' }

function Ticket({ t }) {
  const st = STATUS[t.status]
  return (
    <article className="pred-ticket card">
      <div className="pred-ticket-head">
        <span className={`pred-pill ${st.cls}`}>{st.label}</span>
        <small>{formatDateTime(t.created_at)}</small>
      </div>

      <ul className="pred-ticket-picks">
        {t.ticket_picks.map((p) => {
          const m = p.matches
          const live = m.status === 'live'
          return (
            <li key={p.id}>
              <span>{PICK_ICON[p.status]}</span>
              <div>
                <strong>{m.home_team} x {m.away_team}</strong>
                <small>
                  {p.pick_result && resultLabel(p.pick_result, m)}
                  {p.pick_result && p.pick_btts != null && ' · '}
                  {p.pick_btts != null && `Ambas marcam: ${p.pick_btts ? 'Sim' : 'Não'}`}
                </small>
              </div>
              <em>
                {m.status === 'scheduled'
                  ? formatDateTime(m.kickoff_at)
                  : `${m.home_score ?? 0}–${m.away_score ?? 0}${live ? ` · ${m.minute ?? ''}'` : ''}`}
              </em>
            </li>
          )
        })}
      </ul>

      <div className="pred-ticket-foot">
        <span>Apostou <b>🪙 {t.stake}</b> · {formatMult(Number(t.multiplier))}</span>
        {t.status === 'pending' && <span>Pode ganhar <b>🪙 {t.potential_coins}</b></span>}
        {t.status === 'won' && (
          <span className="won">+🪙 {t.reward_coins} · +{t.reward_xp} XP · ⚡+{t.reward_energy}</span>
        )}
        {t.status === 'lost' && <span className="lost">−🪙 {t.stake}</span>}
        {t.status === 'void' && <span>Moedas devolvidas</span>}
      </div>
    </article>
  )
}

export default function TicketsSection({ onWalletChange }) {
  const [tickets, setTickets] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('open')

  const load = useCallback(async () => {
    try {
      setTickets(await fetchTickets())
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

  return (
    <>
      <div className="pred-seg small">
        <button type="button" className={tab === 'open' ? 'is-on' : ''} onClick={() => setTab('open')}>Abertos</button>
        <button type="button" className={tab === 'done' ? 'is-on' : ''} onClick={() => setTab('done')}>Finalizados</button>
      </div>
      <div className="pred-list">
        {loading && <p className="pred-empty">Carregando…</p>}
        {!loading && error && <p className="pred-empty">{error}</p>}
        {!loading && !error && list.length === 0 && (
          <p className="pred-empty">
            {tab === 'open' ? 'Você não tem bilhetes em andamento.' : 'Nenhum bilhete finalizado ainda.'}
          </p>
        )}
        {list.map((t) => <Ticket key={t.id} t={t} />)}
      </div>
    </>
  )
}
