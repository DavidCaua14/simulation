import { CalendarClock, FastForward, Hourglass, Lock, Play, Radio, ShieldAlert, Shirt, TriangleAlert, Trophy, Zap } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import FormDots from './FormDots'
import stadium from '../../home/assets/temporadas.webp'
import { COMP_NAME, COMP_SHORT, COMP_THEME, describeMatch, ordinal, venueLabel } from '../utils/seasonUtils'
import { reputationTier } from '../utils/managerUtils'

const toForm = (arr = []) => [...arr].reverse()

function Side({ clubId, mine, pos, form, align, knockout }) {
  const club = getClubById(clubId)
  return (
    <div className={`nm-side ${align} ${mine ? 'is-mine' : ''}`}>
      <span className="nm-crest" style={{ '--cc': club?.colors?.[0] || '#33415c' }}>
        <ClubCrest clubId={clubId} size={62} />
      </span>
      <b className="nm-club">{club?.name}</b>
      {mine && <span className="nm-you">Seu time</span>}
      <span className="nm-pos">{pos ? `${ordinal(pos)} na tabela` : knockout ? 'Mata-mata' : 'Início da campanha'}</span>
      <FormDots form={toForm(form)} />
    </div>
  )
}

// DIA DE JOGO do seu clube: confronto, situação da escalação e o botão para entrar em campo.
export function MatchdayHero({ next, myClub, myPos, lineup, canPlay, blockedText, busy, onPlay, onLineup }) {
  const m = next.match
  const t = COMP_THEME[next.competition]
  const venue = venueLabel(m)
  const oppPos = next.opponent_position
  const errors = lineup?.errors ?? 0
  const warnings = lineup?.warnings ?? 0
  const firstIssue = lineup?.issues?.[0]
  return (
    <section className="nm" style={{ '--c1': t.c1, '--c2': t.c2 }} aria-label="Próxima partida">
      <img className="nm-bg" src={stadium} alt="" />
      <span className="nm-shade" aria-hidden="true" />
      <span className="nm-lights" aria-hidden="true" />

      <header className="nm-head">
        <CompEmblem comp={next.competition} size={30} />
        <span className="nm-head-txt">
          <small>Dia de jogo</small>
          <b>{COMP_NAME[next.competition]}</b>
        </span>
        <span className="nm-round">{describeMatch(m)}</span>
      </header>

      <div className="nm-versus">
        <Side clubId={m.home} mine={m.home === myClub} pos={m.home === myClub ? myPos : next.form?.opp?.length ? oppPos : null} knockout={!['league', 'group'].includes(m.stage)} form={m.home === myClub ? next.form?.mine : next.form?.opp} align="left" />
        <div className="nm-mid">
          <span className="nm-vs">VS</span>
          {venue && <span className={`nm-venue ${m.venue === 'home' && !m.neutral ? 'is-home' : ''}`}>{venue}</span>}
        </div>
        <Side clubId={m.away} mine={m.away === myClub} pos={m.away === myClub ? myPos : next.form?.opp?.length ? oppPos : null} knockout={!['league', 'group'].includes(m.stage)} form={m.away === myClub ? next.form?.mine : next.form?.opp} align="right" />
      </div>

      <button type="button" className={`nm-ready ${errors ? 'is-bad' : warnings ? 'is-warn' : 'is-ok'}`} onClick={onLineup}>
        {errors ? <ShieldAlert size={16} /> : warnings ? <TriangleAlert size={16} /> : <Shirt size={16} />}
        <span>
          <b>{errors ? 'Escalação com problema' : warnings ? `Escalação pronta · ${warnings} alerta${warnings > 1 ? 's' : ''}` : `Escalação pronta · ${lineup?.formation || ''}`}</b>
          <small>{firstIssue ? firstIssue.text : 'Toque para revisar titulares, banco e táticas'}</small>
        </span>
      </button>

      <div className="nm-cta">
        <button type="button" className={`gx-btn nm-play ${canPlay && !errors ? 'is-ready' : ''}`} disabled={busy || !canPlay || errors > 0} onClick={onPlay}>
          {busy ? (
            <>
              <span className="nm-spin" /> Entrando em campo…
            </>
          ) : !canPlay ? (
            <>
              <Lock size={17} /> {blockedText}
            </>
          ) : errors ? (
            <>
              <ShieldAlert size={18} /> Corrija a escalação
            </>
          ) : (
            <>
              <Play size={20} fill="currentColor" /> Ir para o jogo
              <span className="nm-cost" title="Custa 1 de energia">
                <Zap size={13} fill="currentColor" />1
              </span>
            </>
          )}
        </button>
        <small>A partida é simulada ao vivo: você pode mexer no time durante o jogo.</small>
      </div>
    </section>
  )
}

// Partida interrompida (app fechado no meio do jogo): retomar de onde parou, sem gastar energia de novo
export function LiveHero({ onResume, busy }) {
  return (
    <section className="nm is-free is-live" aria-label="Partida em andamento">
      <img className="nm-bg" src={stadium} alt="" />
      <span className="nm-shade" aria-hidden="true" />
      <div className="nm-free-body">
        <p>
          <Radio size={16} /> Você tem uma <b>partida em andamento</b>. O jogo está parado esperando o treinador voltar ao banco.
        </p>
      </div>
      <div className="nm-cta">
        <button type="button" className="gx-btn nm-play is-ready" disabled={busy} onClick={onResume}>
          {busy ? <span className="nm-spin" /> : <Play size={20} fill="currentColor" />} Voltar para o jogo
        </button>
      </div>
    </section>
  )
}

// SEM CLUBE: o tempo passa dia a dia e as propostas chegam conforme a reputação
export function UnemployedHero({ coach, offersCount, advancing, onAdvanceDay, onWait, onOffers }) {
  const rep = reputationTier(coach.reputation)
  const last = coach.spell?.club_id || null
  return (
    <section className="uh" aria-label="Sem clube">
      <div className="uh-top">
        <span className="uh-icon">
          <Hourglass size={22} />
        </span>
        <div>
          <small>Treinador sem clube</small>
          <h2>À espera de uma proposta</h2>
        </div>
      </div>
      <p className="uh-text">
        {coach.unemployed_days > 0 ? `Há ${coach.unemployed_days} dia${coach.unemployed_days > 1 ? 's' : ''} sem trabalho. ` : ''}
        Os campeonatos seguem normalmente. Clubes procuram treinadores conforme sua <b>reputação ({rep.label})</b> e as crises que surgem pelo caminho.
      </p>
      {last && (
        <p className="uh-last">
          Último clube: <ClubCrest clubId={last} size={16} /> {getClubById(last)?.name}
        </p>
      )}
      {offersCount > 0 ? (
        <button type="button" className="gx-btn uh-cta is-offer" onClick={onOffers}>
          <Trophy size={18} /> {offersCount === 1 ? 'Ver a proposta recebida' : `Ver ${offersCount} propostas`}
        </button>
      ) : (
        <div className="uh-actions">
          <button type="button" className="gx-btn-ghost" disabled={advancing} onClick={onAdvanceDay}>
            <CalendarClock size={17} /> Avançar 1 dia
          </button>
          <button type="button" className="gx-btn" disabled={advancing} onClick={onWait}>
            {advancing ? <span className="nm-spin" /> : <FastForward size={18} fill="currentColor" />} Aguardar proposta
          </button>
        </div>
      )}
    </section>
  )
}

// DIA SEM JOGO do seu clube: as outras competições andam
export function FreeDayHero({ event, calendar, advancing, onAdvance }) {
  const batch = []
  for (const e of calendar) {
    if (e.kind !== 'free') break
    batch.push(e)
  }
  const compId = event.competition
  const t = COMP_THEME[compId]
  return (
    <section className="nm is-free" style={{ '--c1': t.c1, '--c2': t.c2 }} aria-label="Dia sem jogo">
      <img className="nm-bg" src={stadium} alt="" />
      <span className="nm-shade" aria-hidden="true" />
      <header className="nm-head">
        <CompEmblem comp={compId} size={30} />
        <span className="nm-head-txt">
          <small>Seu time folga</small>
          <b>{COMP_NAME[compId]}</b>
        </span>
      </header>
      <div className="nm-free-body">
        <p>
          Dia de treino. O elenco <b>recupera a condição física</b> enquanto a rodada dos outros campeonatos acontece.
        </p>
        {batch.length > 1 && (
          <ul className="nm-free-list">
            {batch.slice(0, 4).map((e) => (
              <li key={`${e.comp}-${e.stage}-${e.round}`}>
                <CompEmblem comp={e.comp} size={16} />
                <b>{COMP_SHORT[e.comp]}</b>
                <span>{e.label}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="nm-cta">
        <button type="button" className="gx-btn nm-play is-advance" disabled={advancing} onClick={onAdvance}>
          {advancing ? (
            <>
              <span className="nm-spin" /> Simulando…
            </>
          ) : (
            <>
              <FastForward size={20} fill="currentColor" /> Avançar até o próximo jogo
              <span className="nm-cost free">sem energia</span>
            </>
          )}
        </button>
      </div>
    </section>
  )
}
