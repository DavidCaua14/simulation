import { useEffect, useMemo, useState } from 'react'
import { Ambulance, ArrowDown, ArrowLeftRight, ArrowUp, Ban, Building2, Coins, Crown, Megaphone, Sparkles, Star, Trophy, UserX } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { tierOf } from '../../cards/data/tiers'
import { getClubById } from '../../club/data/clubs'
import RoundResults from './RoundResults'
import CompEmblem from '../ui/CompEmblem'
import StandingsTable from './StandingsTable'
import Bracket from './Bracket'
import MatchStats from './MatchStats'
import useStandings from '../hooks/useStandings'
import { boardMood, fansMood } from '../utils/managerUtils'
import { COMP_NAME, RESULT_LABEL, describeMatch } from '../utils/seasonUtils'
import { useAudio } from '../../audio/AudioContext'

function Delta({ v, suffix = '' }) {
  const n = Number(v) || 0
  if (Math.abs(n) < 0.05) return <span className="pm-d is-zero">=</span>
  return (
    <span className={`pm-d ${n > 0 ? 'is-up' : 'is-down'}`}>
      {n > 0 ? <ArrowUp size={12} /> : <ArrowDown size={12} />}
      {Math.abs(n).toFixed(Math.abs(n) < 1 ? 1 : 0)}
      {suffix}
    </span>
  )
}

function headline(s) {
  const mine = s.my_goals
  const opp = s.opp_goals
  if (s.fired) return 'A diretoria decidiu pela sua saída.'
  if (s.competition_result === 'Campeão') return 'É CAMPEÃO! Noite histórica para o clube.'
  if (s.eliminated) return 'Eliminado. A torcida cobra explicações.'
  if (s.advanced) return 'Classificado! O time segue vivo na competição.'
  if (s.result === 'win' && s.expected < 0.4) return 'Vitória de peso contra um adversário mais forte!'
  if (s.result === 'win' && mine - opp >= 3) return 'Goleada! Atuação dominante do seu time.'
  if (s.result === 'win') return 'Vitória importante. Trabalho bem feito.'
  if (s.result === 'draw' && s.expected > 0.62) return 'Empate com sabor de derrota: era jogo para vencer.'
  if (s.result === 'draw') return 'Empate. Um ponto somado.'
  if (s.expected > 0.6) return 'Derrota inesperada. A pressão aumenta.'
  return 'Derrota. Hora de ajustar o time.'
}

// PÓS-JOGO do treinador: resultado, reação da diretoria e da torcida, reputação, departamento médico,
// a rodada completa e a classificação atualizada.
export default function PostMatch({ summary: s, seasonId, byComp, onClose, onOffers, box, onOpenBox }) {
  const [tab, setTab] = useState('summary')
  const { playSfx } = useAudio()
  useEffect(() => {
    if (s.level_up) playSfx('levelup')
  }, [s.level_up, playSfx])
  const home = getClubById(s.home)
  const away = getClubById(s.away)
  const mineIsHome = s.home === s.my_club
  const isTable = s.stage === 'league' || s.stage === 'group'
  const qualified = s.tie_winner && s.stage !== 'final' && (s.leg === 2 || s.leg == null) ? getClubById(s.tie_winner) : null
  const { rows } = useStandings(isTable ? seasonId : null, s.competition, s.group || null, `pm${s.fixture_id}`)
  const roundMatches = useMemo(
    () => [{ id: s.fixture_id, home: s.home, away: s.away, hg: s.home_goals, ag: s.away_goals, hp: s.pens?.[0], ap: s.pens?.[1], group: s.group, mine: true }, ...(s.round_results || [])],
    [s],
  )
  const motmClub = s.motm ? (s.motm.side === 'h' ? s.home : s.away) : null

  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label="Resumo da partida">
      <div className="sn-modal">
        <header className="sn-modal-head">
          <CompEmblem comp={s.competition} size={28} />
          <span>
            <small>{COMP_NAME[s.competition]}</small>
            <b>{describeMatch(s)}</b>
          </span>
          <span className="pm-live is-done">Fim de jogo</span>
        </header>

        <div className="sn-board">
          <div className={`sn-board-team ${mineIsHome ? 'is-mine' : ''}`}>
            <ClubCrest clubId={s.home} size={58} />
            <span>{home?.name}</span>
          </div>
          <div className="sn-board-score">
            <b>{s.home_goals}</b>
            <i>×</i>
            <b>{s.away_goals}</b>
          </div>
          <div className={`sn-board-team ${!mineIsHome ? 'is-mine' : ''}`}>
            <ClubCrest clubId={s.away} size={58} />
            <span>{away?.name}</span>
          </div>
        </div>

        <div className="sn-reveal">
          <div className={`sn-banner r-${s.result}`}>{RESULT_LABEL[s.result]}</div>
          {s.pens && <p className="sn-note">Pênaltis: {s.pens[0]} × {s.pens[1]}</p>}
          {qualified && (
            <p className="sn-note">
              Classificado: <ClubCrest clubId={s.tie_winner} size={16} /> <b>{qualified.name}</b>
            </p>
          )}
          <p className="pm-head">{headline(s)}</p>

          <div className="sn-seg">
            {[
              ['summary', 'Resumo'],
              ['stats', 'Números'],
              ['round', 'Rodada'],
              ['table', isTable ? 'Tabela' : 'Chave'],
            ].map(([id, label]) => (
              <button key={id} type="button" className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
                {label}
              </button>
            ))}
          </div>

          {tab === 'summary' && (
            <>
              {s.fired && (
                <div className="pm-fired">
                  <UserX size={22} />
                  <div>
                    <b>Você foi demitido</b>
                    <span>Motivo: {s.fire_reason}. Seu histórico continua: avance os dias para receber propostas de outros clubes.</span>
                  </div>
                </div>
              )}

              <section className="pm-impact">
                <div className={`pm-imp t-${boardMood(s.board.after).tone}`}>
                  <Building2 size={16} />
                  <span>
                    <small>Diretoria</small>
                    <b>{boardMood(s.board.after).label}</b>
                  </span>
                  <Delta v={s.board.delta} />
                </div>
                <div className={`pm-imp t-${fansMood(s.fans.after).tone}`}>
                  <Megaphone size={16} />
                  <span>
                    <small>Torcida</small>
                    <b>{fansMood(s.fans.after).label}</b>
                  </span>
                  <Delta v={s.fans.delta} />
                </div>
                <div className="pm-imp t-rep">
                  <Star size={16} />
                  <span>
                    <small>Reputação</small>
                    <b>{s.reputation.after}</b>
                  </span>
                  <Delta v={s.reputation.delta} />
                </div>
              </section>

              {s.motm && (
                <div className="pm-motm">
                  <Crown size={18} />
                  <ClubCrest clubId={motmClub} size={22} />
                  <span>
                    <small>Craque do jogo</small>
                    <b>{s.motm.name}</b>
                  </span>
                  <em>{Number(s.motm.rating).toFixed(1)}</em>
                </div>
              )}

              {(s.injuries?.length > 0 || s.suspensions?.length > 0) && (
                <ul className="pm-med">
                  {s.injuries?.map((p) => (
                    <li key={`i${p.player}`}>
                      <Ambulance size={15} /> <b>{p.name}</b> — {p.injury}, fora por {p.days} dia{p.days > 1 ? 's' : ''}
                    </li>
                  ))}
                  {s.suspensions?.map((p) => (
                    <li key={`s${p.player}`}>
                      <Ban size={15} /> <b>{p.name}</b> — suspenso por {p.games} jogo{p.games > 1 ? 's' : ''}
                    </li>
                  ))}
                </ul>
              )}

              {s.table && s.table.before && s.table.after && (
                <p className="pm-table">
                  Tabela: {s.table.before}º → <b>{s.table.after}º</b>
                </p>
              )}

              <div className="sn-rewards">
                <span className="xp">+{s.rewards.xp} XP</span>
                <span className="coins">
                  <Coins size={13} /> +{s.rewards.coins}
                </span>
              </div>

              {box && (
                <button type="button" className="sn-boxwin" style={{ '--tier': tierOf(box.tier).color, '--glow': tierOf(box.tier).glow }} onClick={onOpenBox}>
                  <img src={tierOf(box.tier).closed} alt="" draggable="false" />
                  <span>
                    <b>Você ganhou uma caixa {tierOf(box.tier).label}!</b>
                    <small>Toque para abrir agora · ou abra depois na caixa de entrada</small>
                  </span>
                </button>
              )}

              {s.level_up && (
                <div className="sn-levelup">
                  <Sparkles size={18} /> SUBIU DE NÍVEL! Agora você é nível <b>{s.new_level}</b>
                </div>
              )}

              {s.competition_finished && (
                <div className="sn-compdone">
                  <Trophy size={18} />
                  <div>
                    <b>{COMP_NAME[s.competition]} encerrada</b>
                    <span>
                      Sua campanha: {s.competition_result || '—'}
                      {s.competition_bonus ? ` · +${s.competition_bonus.xp} XP · +${s.competition_bonus.coins} moedas` : ''}
                    </span>
                    {s.champion && (
                      <span>
                        Campeão: <ClubCrest clubId={s.champion} size={14} /> {getClubById(s.champion)?.name}
                      </span>
                    )}
                  </div>
                </div>
              )}

              {s.offer && (
                <button type="button" className="sn-offer-alert" onClick={onOffers}>
                  <ArrowLeftRight size={18} />
                  <ClubCrest clubId={s.offer.club_id} size={22} />
                  <span>
                    <b>{getClubById(s.offer.club_id)?.name}</b> quer você como treinador! Toque para ver.
                  </span>
                </button>
              )}

              {s.season_finished && (
                <div className="sn-compdone season">
                  <Trophy size={18} />
                  <div>
                    <b>Temporada encerrada!</b>
                    <span>Veja o balanço e comece a próxima temporada.</span>
                  </div>
                </div>
              )}
            </>
          )}

          {tab === 'stats' && <MatchStats stats={s.stats} home={s.home} away={s.away} />}
          {tab === 'round' && <RoundResults matches={roundMatches} myClub={s.my_club} title="Jogos da rodada" />}
          {tab === 'table' &&
            (isTable ? (
              <StandingsTable rows={rows} myClub={s.my_club} mode={s.stage === 'group' ? 'group' : 'league'} />
            ) : (
              <Bracket fixtures={byComp[s.competition] || []} myClub={s.my_club} />
            ))}

          <button type="button" className="gx-btn sn-continue" onClick={onClose}>
            {s.season_finished ? 'Ver balanço da temporada' : 'Continuar'}
          </button>
        </div>
      </div>
    </div>
  )
}
