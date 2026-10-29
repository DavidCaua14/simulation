import WorldPanel from '../world/WorldPanel'
import JobTerms from '../world/JobTerms'
import StandingsTable from '../components/StandingsTable'
import { useEffect, useRef, useState } from 'react'
import { Briefcase, CalendarRange, Coins, DoorOpen, Flag, History, Target, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import TrophyCabinet from '../components/TrophyCabinet'
import { Stars } from '../components/CoachStatusCard'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { fetchHistory } from '../services/managerApi'
import { END_REASON, reputationTier, winRate } from '../utils/managerUtils'
import { COMP_SHORT, fmt, seasonLabel } from '../utils/seasonUtils'

const VIEWS = [
  { id: 'profile', label: 'Perfil' },
  { id: 'world', label: 'Gestão' },
  { id: 'offers', label: 'Propostas' },
  { id: 'clubs', label: 'Clubes' },
  { id: 'seasons', label: 'Temporadas' },
]

const when = (year, day) => `${year}${day != null ? ` · dia ${day}` : ''}`

function OfferCard({ o, employed, busy, onRespond, onRefresh }) {
  const [confirm, setConfirm] = useState(false)
  const club = getClubById(o.club_id)
  const ctx = o.context || {}
  return (
    <article className="of" style={{ '--cc': club?.colors?.[0] || '#2a3550' }}>
      <header>
        <ClubCrest clubId={o.club_id} size={48} />
        <div>
          <small>Proposta para treinador</small>
          <b>{club?.name}</b>
          <span className={`of-dead ${o.days_left <= 1 ? 'urgent' : ''}`}>{o.days_left > 0 ? `Responda em ${o.days_left} dia${o.days_left > 1 ? 's' : ''}` : 'Último dia'}</span>
        </div>
      </header>
      {o.pitch && <p className="of-pitch">“{o.pitch}”</p>}
      <ul className="of-facts">
        {ctx.position != null && (
          <li>
            <Flag size={13} /> Hoje: {ctx.position}º na liga
          </li>
        )}
        {ctx.objective && (
          <li>
            <Target size={13} /> Objetivo: {ctx.objective}
          </li>
        )}
        {o.bonus_coins > 0 && (
          <li>
            <Coins size={13} /> Luvas: {fmt(o.bonus_coins)} moedas
          </li>
        )}
      </ul>
      {o.salary != null && <JobTerms key={`${o.id}:${o.negotiation_round}`} offer={o} onRefresh={onRefresh} />}
      {confirm ? (
        <div className="of-confirm">
          <p>{employed ? 'Você deixa o clube atual agora. A temporada continua de onde parou, no novo clube, com o elenco dele.' : 'Você assume o clube agora e a temporada continua de onde parou.'}</p>
          <div className="of-actions">
            <button type="button" className="gx-btn-ghost" onClick={() => setConfirm(false)} disabled={busy}>
              Voltar
            </button>
            <button type="button" className="gx-btn" onClick={() => onRespond(o.id, true)} disabled={busy}>
              {busy ? <span className="nm-spin" /> : null} Assinar contrato
            </button>
          </div>
        </div>
      ) : (
        <div className="of-actions">
          <button type="button" className="gx-btn-ghost" onClick={() => onRespond(o.id, false)} disabled={busy}>
            Recusar
          </button>
          <button type="button" className="gx-btn" onClick={() => setConfirm(true)} disabled={busy}>
            Aceitar
          </button>
        </div>
      )}
    </article>
  )
}

// CARREIRA do treinador: perfil e números, propostas, clubes por onde passou e temporadas.
// O histórico continua mesmo trocando de clube no meio da temporada (cada passagem é registrada).
export default function CareerTab({ ctx, initialView, actions }) {
  const { hub, busy } = ctx
  const coach = hub.coach
  const [view, setView] = useState(initialView || (hub.offers.length && coach.status === 'unemployed' ? 'offers' : 'profile'))
  const [hist, setHist] = useState(null)
  const [confirmResign, setConfirmResign] = useState(false)
  const reqKey = `${coach.matches}|${coach.status}|${coach.club_id}|${hub.season.status}|${hub.season.id}`
  const lastKey = useRef(null)

  useEffect(() => {
    if (initialView) setView(initialView)
  }, [initialView])

  useEffect(() => {
    if (lastKey.current === reqKey) return undefined
    lastKey.current = reqKey
    let alive = true
    fetchHistory()
      .then((d) => alive && setHist(d))
      .catch(() => alive && setHist({ spells: [], seasons: [] }))
    return () => {
      alive = false
    }
  }, [reqKey])

  const rep = reputationTier(coach.reputation)
  const club = coach.club_id ? getClubById(coach.club_id) : null
  const rate = winRate(coach.wins, coach.draws, coach.losses)

  return (
    <div className="sn-page">
      <section className="co" style={{ '--cc': club?.colors?.[0] || '#24314d' }}>
        <div className="co-top">
          <span className="co-crest">{club ? <ClubCrest clubId={club.id} size={58} /> : <Briefcase size={28} />}</span>
          <div className="co-id">
            <small>Treinador · {hub.career.country || 'Brasil'}</small>
            <h2>{hub.career.nickname}</h2>
            <span className="co-club">{club ? club.name : 'Sem clube'}</span>
          </div>
        </div>
        <div className="co-rep">
          <Stars value={rep.stars} />
          <b>{rep.label}</b>
          <span>
            Reputação <em>{Math.round(coach.reputation)}</em>/100
          </span>
          <i className="co-repbar">
            <em style={{ width: `${coach.reputation}%` }} />
          </i>
        </div>
        <div className="co-nums">
          <span>
            <b>{coach.matches}</b>
            <small>Jogos</small>
          </span>
          <span className="w">
            <b>{coach.wins}</b>
            <small>Vitórias</small>
          </span>
          <span className="d">
            <b>{coach.draws}</b>
            <small>Empates</small>
          </span>
          <span className="l">
            <b>{coach.losses}</b>
            <small>Derrotas</small>
          </span>
          <span>
            <b>{rate}%</b>
            <small>Aproveit.</small>
          </span>
          <span className="gold">
            <b>{coach.titles}</b>
            <small>Títulos</small>
          </span>
        </div>
      </section>

      <div className="sn-seg cw-nav" role="tablist" aria-label="Áreas da carreira">
        {VIEWS.filter(v => v.id !== 'world' || hub.world).map((v) => (
          <button key={v.id} type="button" role="tab" aria-selected={view === v.id} className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
            {v.id === 'offers' && hub.offers.length > 0 && <em>{hub.offers.length}</em>}
          </button>
        ))}
      </div>

      {view === 'world' && hub.world && <WorldPanel hub={hub} onRefresh={actions.refresh} onReport={actions.openReport} onHome={() => actions.goTab('home')} />}
      {view === 'profile' && (
        <>
          <section className="sn-sec">
            <h2 className="gx-title">Conquistas</h2>
            {hub.world && <JobTerms coach={hub.world.coach} employed={coach.status === 'employed'} onRefresh={actions.refresh} />}
            <TrophyCabinet history={hist?.seasons || []} titles={coach.titles} />
          </section>
          <section className="sn-sec">
            <h2 className="gx-title">Números da carreira</h2>
            <div className="co-grid">
              <span>
                <b>{coach.gf}</b>
                <small>Gols marcados</small>
              </span>
              <span>
                <b>{coach.ga}</b>
                <small>Gols sofridos</small>
              </span>
              <span>
                <b>{coach.seasons}</b>
                <small>Temporadas completas</small>
              </span>
              <span>
                <b>{(hist?.spells || []).length}</b>
                <small>Clubes comandados</small>
              </span>
              <span className={coach.fired_count ? 'bad' : ''}>
                <b>{coach.fired_count}</b>
                <small>Demissões</small>
              </span>
              <span>
                <b>{fmt(hub.career.coins)}</b>
                <small>Moedas</small>
              </span>
            </div>
            <p className="sn-hint">
              Reputação sobe com vitórias acima do esperado, títulos e objetivos cumpridos — e cai com demissões e campanhas ruins. Quanto maior, maiores os clubes que
              procuram você.
            </p>
          </section>
          {coach.status === 'employed' && (
            <section className="sn-sec co-danger">
              {confirmResign ? (
                <div className="of-confirm">
                  <p>Pedir demissão custa um pouco de reputação. Você fica sem clube e espera propostas com o passar dos dias. A temporada continua.</p>
                  <div className="of-actions">
                    <button type="button" className="gx-btn-ghost" onClick={() => setConfirmResign(false)}>
                      Ficar
                    </button>
                    <button type="button" className="gx-btn is-danger" disabled={busy === 'resign'} onClick={actions.resign}>
                      <DoorOpen size={16} /> Confirmar demissão
                    </button>
                  </div>
                </div>
              ) : (
                <button type="button" className="sn-link is-danger" onClick={() => setConfirmResign(true)}>
                  <DoorOpen size={15} /> Pedir demissão do clube
                </button>
              )}
            </section>
          )}
        </>
      )}

      {view === 'offers' && (
        <div className="sn-stack">
          {hub.offers.length === 0 ? (
            <EmptyState
              icon={Briefcase}
              title="Nenhuma proposta no momento"
              text={
                coach.status === 'unemployed'
                  ? 'Avance os dias no Início: os clubes procuram treinadores conforme sua reputação.'
                  : 'Bons resultados chamam atenção. Clubes em crise também procuram treinadores durante a temporada.'
              }
            />
          ) : (
            hub.offers.map((o) => <OfferCard key={o.id} o={o} employed={coach.status === 'employed'} busy={busy === `offer:${o.id}`} onRespond={actions.respondOffer} onRefresh={actions.refresh} />)
          )}
          {hub.offer_history?.length > 0 && (
            <section className="sn-sec">
              <h2 className="gx-title">Respondidas</h2>
              <ul className="of-hist">
                {hub.offer_history.map((h) => (
                  <li key={h.id}>
                    <ClubCrest clubId={h.club_id} size={20} /> {getClubById(h.club_id)?.name}
                    <em className={`is-${h.status}`}>{{ accepted: 'Aceita', declined: 'Recusada', expired: 'Expirou' }[h.status] || h.status}</em>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
      )}

      {view === 'clubs' && (
        <section className="sn-sec">
          {!hist ? (
            <div className="st-sk row" />
          ) : hist.spells.length === 0 ? (
            <EmptyState icon={History} title="Nenhum clube ainda" />
          ) : (
            <ol className="sp-list">
              {hist.spells.map((sp) => {
                const c = getClubById(sp.club_id)
                return (
                  <li key={sp.id} className={`sp ${sp.current ? 'is-current' : ''}`} style={{ '--cc': c?.colors?.[0] || '#2a3550' }}>
                    <ClubCrest clubId={sp.club_id} size={44} />
                    <div className="sp-body">
                      <b>{c?.name}</b>
                      <small>
                        <CalendarRange size={12} /> {when(sp.started_year, sp.started_day)} → {sp.current ? 'atual' : when(sp.ended_year, sp.ended_day)}
                      </small>
                      <span className="sp-rec">
                        {sp.matches} jogos · <em className="w">{sp.wins}V</em> <em className="d">{sp.draws}E</em> <em className="l">{sp.losses}D</em> · {sp.gf}:{sp.ga} ·{' '}
                        {winRate(sp.wins, sp.draws, sp.losses)}%
                      </span>
                    </div>
                    <span className="sp-end">
                      {sp.titles > 0 && (
                        <em className="gold">
                          <Trophy size={12} /> {sp.titles}
                        </em>
                      )}
                      {sp.current ? <em className="now">No cargo</em> : <em className={`end-${sp.end_reason}`}>{END_REASON[sp.end_reason] || sp.end_reason}</em>}
                    </span>
                  </li>
                )
              })}
            </ol>
          )}
        </section>
      )}

      {view === 'seasons' && (
        <section className="sn-sec">
          {!hist ? (
            <div className="st-sk row" />
          ) : (
            <ol className="sy-list">
              {hist.seasons.map((s) => (
                <li key={s.id} className="sy">
                  <header>
                    <b>Temporada {seasonLabel(s.year, s.region)}</b>
                    <span className="sy-clubs">
                      {(s.clubs || []).map((id) => (
                        <ClubCrest key={id} clubId={id} size={20} />
                      ))}
                    </span>
                    <span className="sy-rec">
                      <em className="w">{s.wins}V</em> <em className="d">{s.draws}E</em> <em className="l">{s.losses}D</em>
                    </span>
                    {s.status === 'active' && <em className="gx-tag is-live">Em andamento</em>}
                  </header>
                  {s.summary?.competitions?.length > 0 && (
                    <ul className="sy-comps">
                      {s.summary.competitions
                        .filter((c) => c.player_result)
                        .map((c) => (
                          <li key={c.competition} className={c.player_result === 'Campeão' ? 'is-gold' : ''}>
                            <CompEmblem comp={c.competition} size={16} /> {COMP_SHORT[c.competition]}: <b>{c.player_result}</b>
                          </li>
                        ))}
                    </ul>
                  )}
                  {Object.entries(s.final_tables || {}).map(([competition, rows]) => (
                    <details className="sn-sec" key={competition}>
                      <summary>Classificação final · {COMP_SHORT[competition] || competition}</summary>
                      <StandingsTable rows={rows} myClub={s.club_id} zones={[]} mode="history" />
                    </details>
                  ))}
                  {s.summary?.transition?.qualified && Object.entries(s.summary.transition.qualified).map(([competition, clubs]) => (
                    <p className="sn-hint" key={competition}>Classificados · {COMP_SHORT[competition] || competition}: {clubs.map((id) => getClubById(id)?.name || id).join(', ')}</p>
                  ))}
                  {s.objectives?.length > 0 && (
                    <ul className="sy-objs">
                      {s.objectives
                        .filter((o) => o.status !== 'void')
                        .map((o, i) => (
                          <li key={i} className={`is-${o.status}`}>
                            <ClubCrest clubId={o.club_id} size={14} /> {o.label}
                          </li>
                        ))}
                    </ul>
                  )}
                </li>
              ))}
            </ol>
          )}
        </section>
      )}
    </div>
  )
}
