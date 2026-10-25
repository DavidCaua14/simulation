import { useEffect, useState } from 'react'
import { Ambulance, Crown } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import Sheet from '../ui/Sheet'
import MatchStats from './MatchStats'
import { fetchMatchReport } from '../services/managerApi'
import { MAJOR_EVENTS, eventText } from '../utils/managerUtils'
import { COMP_NAME, describeMatch } from '../utils/seasonUtils'

// SÚMULA de qualquer partida da temporada: placar, lances, números e notas dos jogadores.
export default function MatchReport({ fixtureId, onClose }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('events')
  useEffect(() => {
    let alive = true
    fetchMatchReport(fixtureId)
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(e.message))
    return () => {
      alive = false
    }
  }, [fixtureId])

  const home = data && getClubById(data.home)
  const away = data && getClubById(data.away)
  const evs = (data?.events || []).filter((e) => MAJOR_EVENTS.has(e.kind) || e.kind === 'sub' || e.kind === 'yellow' || e.kind.startsWith('so_'))
  const motm = data?.summary?.motm?.id || data?.stats?.motm
  const sc = data?.score || [data?.home_goals, data?.away_goals]

  return (
    <Sheet kicker={data ? COMP_NAME[data.competition] : 'Súmula'} title={data ? describeMatch(data) : 'Carregando…'} onClose={onClose} tall>
      {error && <p className="sn-muted sn-center">{error}</p>}
      {!data && !error && <div className="st-sk row" />}
      {data && (
        <div className="mr-rep">
          <div className="sn-board is-compact">
            <div className="sn-board-team">
              <ClubCrest clubId={data.home} size={44} />
              <span>{home?.name}</span>
            </div>
            <div className="sn-board-score">
              <b>{sc[0]}</b>
              <i>×</i>
              <b>{sc[1]}</b>
            </div>
            <div className="sn-board-team">
              <ClubCrest clubId={data.away} size={44} />
              <span>{away?.name}</span>
            </div>
          </div>

          <div className="sn-seg">
            {[
              ['events', 'Lances'],
              ['stats', 'Números'],
              ...(data.players?.length ? [['players', 'Notas']] : []),
            ].map(([id, label]) => (
              <button key={id} type="button" className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
                {label}
              </button>
            ))}
          </div>

          {tab === 'events' &&
            (evs.length ? (
              <ol className="ml-feed is-static">
                {evs.map((e) => (
                  <li key={e.seq} className={`ml-ev k-${e.kind} ${MAJOR_EVENTS.has(e.kind) ? 'is-major' : ''}`}>
                    <span className="ml-min">{e.minute}'</span>
                    {e.side && <ClubCrest clubId={e.side === 'h' ? data.home : data.away} size={16} />}
                    <span className="ml-txt">{eventText(e, e.side === 'h' ? home?.name : away?.name)}</span>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="sn-muted sn-center">Sem lances registrados.</p>
            ))}
          {tab === 'stats' && <MatchStats stats={data.stats} home={data.home} away={data.away} />}
          {tab === 'players' && (
            <div className="ml-lineups">
              {['h', 'a'].map((sd) => (
                <div key={sd} className="ml-lu">
                  <h4>
                    <ClubCrest clubId={sd === 'h' ? data.home : data.away} size={18} /> {(sd === 'h' ? home : away)?.name}
                    <small>{data.formation?.[sd === 'h' ? 0 : 1]}</small>
                  </h4>
                  <ul>
                    {data.players
                      .filter((p) => p.side === sd && p.minutes > 0)
                      .map((p) => (
                        <li key={p.id} className={`st-${p.status}`}>
                          <span className="ml-pos">{p.pos || p.natural}</span>
                          <span className="ml-pn">
                            {p.name}
                            {p.goals > 0 && <em className="ml-g">{'⚽'.repeat(Math.min(p.goals, 4))}</em>}
                            {p.yellow > 0 && <i className="mcard y" />}
                            {p.red > 0 && <i className="mcard r" />}
                            {p.injured && <Ambulance size={11} />}
                            {p.id === motm && <Crown size={12} className="ml-motm" />}
                          </span>
                          <small className="ml-mins">{p.minutes}'</small>
                          <b className="ml-rt">{Number(p.rating).toFixed(1)}</b>
                        </li>
                      ))}
                  </ul>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </Sheet>
  )
}
