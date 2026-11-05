import GameIcon from '../../../components/ui/GameIcon'
import ExitModeButton from '../components/ExitModeButton'
import JobTerms from '../world/JobTerms'
import StandingsTable from '../components/StandingsTable'
import { useEffect, useRef, useState } from 'react'
import { Briefcase, Building2, CalendarRange, DoorOpen, Flag, History, Megaphone, Target, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import TrophyCabinet from '../components/TrophyCabinet'
import { Meter, Stars } from '../components/CoachStatusCard'
import CompEmblem from '../ui/CompEmblem'
import { EmptyState } from '../ui/States'
import { applyVacancy, fetchHistory, fetchOfferClub, fetchVacancies, fetchVacancyClub } from '../services/managerApi'
import { END_REASON, boardMood, fansMood, objectiveProgress, reputationTier, winRate } from '../utils/managerUtils'
import { COMPETITIONS, COMP_SHORT, fmt, seasonLabel } from '../utils/seasonUtils'

const VIEWS = [
  { id: 'profile', label: 'Técnico' },
  { id: 'offers', label: 'Propostas' },
  { id: 'clubs', label: 'Clubes' },
  { id: 'seasons', label: 'Temporadas' },
]

const when = (year, day) => `${year}${day != null ? ` · dia ${day}` : ''}`

const POS_GROUPS = [
  { label: 'Goleiros', codes: ['GOL'] },
  { label: 'Defensores', codes: ['ZAG', 'LD', 'LE'] },
  { label: 'Meio-campistas', codes: ['VOL', 'MC', 'MEI'] },
  { label: 'Atacantes', codes: ['PD', 'PE', 'ATA'] },
]

// Elenco do clube da proposta, por posição (só leitura)
function OfferSquad({ info, clubName, onClose }) {
  const squad = info?.squad || []
  const groups = POS_GROUPS.map((g) => ({ ...g, players: squad.filter((p) => g.codes.includes(p.pos)) }))
  const other = squad.filter((p) => !POS_GROUPS.some((g) => g.codes.includes(p.pos)))
  if (other.length) groups.push({ label: 'Outros', players: other })
  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label={`Elenco do ${clubName}`} onClick={onClose}>
      <div className="sn-modal" onClick={(e) => e.stopPropagation()}>
        <header className="sn-modal-head">
          <span>
            <small>{info?.division ? `${info.division} · ` : ''}Força {info?.strength ?? '—'}</small>
            <b>{clubName}</b>
          </span>
        </header>
        {groups.filter((g) => g.players.length).map((g) => (
          <section key={g.label} className="of-squad">
            <h4>{g.label}</h4>
            <table className="sn-table">
              <thead>
                <tr><th>Jogador</th><th>Pos</th><th>Idade</th><th>Força</th></tr>
              </thead>
              <tbody>
                {g.players.map((p) => (
                  <tr key={p.id}>
                    <td className="club">{p.name}</td>
                    <td>{p.pos}</td>
                    <td>{p.age ?? '—'}</td>
                    <td><b>{p.rating}</b></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        ))}
        <div className="of-actions">
          <button type="button" className="gx-btn" onClick={onClose}>Fechar</button>
        </div>
      </div>
    </div>
  )
}

// Vagas abertas por demissões da IA: candidatura com resposta em alguns dias (limite de candidaturas abertas)
function Vacancies({ employed, version }) {
  const [data, setData] = useState(null)
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState('')
  const [preview, setPreview] = useState(null)
  useEffect(() => {
    let alive = true
    fetchVacancies().then((d) => { if (alive) setData(d) }).catch(() => {})
    return () => { alive = false }
  }, [version])
  if (!data) return null
  const full = data.open_applications >= data.limit
  const apply = async (id) => {
    setBusy(id)
    setError('')
    try {
      setData(await applyVacancy(id))
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }
  const openSquad = async (v) => {
    try {
      setPreview({ name: getClubById(v.club_id)?.name || v.club_id, info: await fetchVacancyClub(v.id) })
    } catch (e) {
      setError(e.message)
    }
  }
  return (
    <section className="sn-sec">
      <h2 className="gx-title">
        <Megaphone size={16} /> Vagas abertas
      </h2>
      <p className="of-vac-note">
        {employed ? 'Empregado ou não, você pode se candidatar.' : 'Sem clube: candidate-se às vagas abertas.'} Candidaturas abertas: {data.open_applications} de {data.limit}. Sua reputação: {data.reputation}.
      </p>
      {error && <p className="of-vac-err">{error}</p>}
      {data.vacancies.length === 0 ? (
        <p className="of-vac-note">Nenhuma vaga aberta. Clubes que vão mal demitem o técnico ao longo da temporada.</p>
      ) : (
        <ul className="of-vac">
          {data.vacancies.map((v) => (
            <li key={v.id}>
              <ClubCrest clubId={v.club_id} size={28} />
              <span className="of-vac-txt">
                <b>{getClubById(v.club_id)?.name || v.club_id}</b>
                <small>
                  {v.division ? `${v.division} · ` : ''}Força {v.strength} · {v.reason} · pede reputação {Math.round(v.required_reputation)}
                </small>
                <small>
                  {v.rejected
                    ? 'O clube recusou sua candidatura.'
                    : v.applied
                      ? `Candidatura enviada: resposta em até ${v.answer_in} dia${v.answer_in === 1 ? '' : 's'}`
                      : `Fecha em ${v.closes_in} dia${v.closes_in === 1 ? '' : 's'}`}
                </small>
              </span>
              <span className="of-vac-actions">
                <button type="button" className="gx-btn-ghost" onClick={() => openSquad(v)}>Ver time</button>
                {!v.applied && !v.rejected && (
                  <button type="button" className="gx-btn" disabled={full || busy === v.id} onClick={() => apply(v.id)}>
                    {busy === v.id ? <span className="nm-spin" /> : null} Candidatar-se
                  </button>
                )}
              </span>
            </li>
          ))}
        </ul>
      )}
      {preview && <OfferSquad info={preview.info} clubName={preview.name} onClose={() => setPreview(null)} />}
    </section>
  )
}

function OfferCard({ o, employed, busy, onRespond, onRefresh }) {
  const [confirm, setConfirm] = useState(false)
  const [info, setInfo] = useState(null)
  const [showSquad, setShowSquad] = useState(false)
  const club = getClubById(o.club_id)
  const ctx = o.context || {}
  useEffect(() => {
    let alive = true
    fetchOfferClub(o.id).then((d) => { if (alive) setInfo(d) }).catch(() => {})
    return () => { alive = false }
  }, [o.id])
  return (
    <article className="of" style={{ '--cc': club?.colors?.[0] || '#2a3550' }}>
      <h3 className="of-title">Oferta de emprego</h3>
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
            <GameIcon name="coins" size={13} /> Luvas: {fmt(o.bonus_coins)} moedas
          </li>
        )}
        {info && (
          <li>
            <Building2 size={13} /> Força do time: <b>{info.strength}</b>
            {info.division ? ` · ${info.division}` : ''}
            {employed && info.current_strength != null ? ` · seu clube atual: ${info.current_strength}` : ''}
          </li>
        )}
      </ul>
      {info && (
        <button type="button" className="gx-btn-ghost of-squad-btn" onClick={() => setShowSquad(true)}>
          Ver time
        </button>
      )}
      {showSquad && <OfferSquad info={info} clubName={club?.name || o.club_id} onClose={() => setShowSquad(false)} />}
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
  const season = hub.season

  return (
    <div className="sn-page">
      <div className="sn-seg cw-nav" role="tablist" aria-label="Áreas da carreira">
        {VIEWS.filter(v => v.id !== 'world' || hub.world).map((v) => (
          <button key={v.id} type="button" role="tab" aria-selected={view === v.id} className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
            {v.id === 'offers' && hub.offers.length > 0 && <em>{hub.offers.length}</em>}
          </button>
        ))}
      </div>

      {view === 'profile' && (
        <>
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


          <section className="cm-block">
            <h3>Desempenho na temporada</h3>
            <div className="cm-cells">
              <span>
                <small>Jogos</small>
                <b>{season.wins + season.draws + season.losses}</b>
              </span>
              <span>
                <small>Vitórias</small>
                <b>{season.wins}</b>
              </span>
              <span>
                <small>Empates</small>
                <b>{season.draws}</b>
              </span>
              <span>
                <small>Derrotas</small>
                <b>{season.losses}</b>
              </span>
            </div>
            {coach.status === 'employed' && (
              <div className="cm-meters">
                <Meter icon={Building2} label="Diretoria" value={coach.board} mood={boardMood(coach.board)} />
                <Meter icon={Megaphone} label="Torcida" value={coach.fans} mood={fansMood(coach.fans)} />
              </div>
            )}
          </section>

          {hub.objectives.length > 0 && coach.status === 'employed' && (
            <section className="cm-block">
              <h3>Objetivos da diretoria</h3>
              <ul className="cm-objs">
                {hub.objectives.map((o) => {
                  const pr = objectiveProgress(o, o.kind === 'league_pos' ? hub.competitions.find((c) => c.id === o.competition)?.table?.played ?? null : null)
                  return (
                    <li key={o.id} className={`is-${o.status} t-${pr.tone}`}>
                      <Trophy size={16} />
                      <span>
                        <b>{o.label}</b>
                        <small>{pr.text}</small>
                      </span>
                      <em>{o.status === 'done' ? 'Cumprido' : o.status === 'failed' ? 'Falhou' : 'Em andamento'}</em>
                    </li>
                  )
                })}
              </ul>
            </section>
          )}

          {hist?.seasons?.length > 0 && (
            <section className="cm-block">
              <h3>Histórico da carreira</h3>
              <table className="sn-table cm-hist">
                <thead>
                  <tr>
                    <th>Temporada</th>
                    <th className="left">Time</th>
                    <th>Posição</th>
                  </tr>
                </thead>
                <tbody>
                  {hist.seasons.map((h) => {
                    const league = (h.summary?.competitions || []).find((c) => c.player_result && COMPETITIONS[c.competition]?.kind === 'league') || (h.summary?.competitions || []).find((c) => c.player_result)
                    return (
                      <tr key={h.id}>
                        <td>{seasonLabel(h.year, h.region)}</td>
                        <td className="left">
                          <span className="cm-hist-club">
                            {(h.clubs || []).slice(0, 2).map((id) => (
                              <ClubCrest key={id} clubId={id} size={18} />
                            ))}
                            {getClubById(h.clubs?.[h.clubs.length - 1])?.name || '—'}
                          </span>
                        </td>
                        <td>{h.status === 'active' ? 'em andamento' : league ? `${league.player_result}` : '—'}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </section>
          )}
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
          <button type="button" className="gx-btn cm-wide" onClick={() => setView('offers')}>
            <Briefcase size={17} /> Propostas {hub.offers.length > 0 && <em className="sn-badge">{hub.offers.length}</em>}
          </button>
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
          <Vacancies employed={coach.status === 'employed'} version={hub.runtime_version} />
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
      <ExitModeButton onExit={actions.exit} />
    </div>
  )
}
