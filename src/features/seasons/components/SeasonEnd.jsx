import { ArrowLeftRight, CircleCheck, CircleX, PartyPopper, Play, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { COMP_NAME, seasonLabel } from '../utils/seasonUtils'

// FIM DE TEMPORADA: campeões, a campanha do seu time, objetivos e o caminho para a próxima.
export default function SeasonEnd({ season, coach, objectives = [], starting, onStartNext, offers = 0, onOffers, nextStartsOn }) {
  const sum = season.summary || {}
  const comps = sum.competitions || []
  const titles = comps.filter((c) => c.player_result === 'Campeão')
  return (
    <section className="se" aria-label="Temporada encerrada">
      <header className="se-head">
        <span className="se-icon">{titles.length ? <PartyPopper size={22} /> : <Trophy size={22} />}</span>
        <div>
          <small>Temporada {seasonLabel(season.year, season.region)} encerrada</small>
          <h2>{titles.length ? `${titles.length} título${titles.length > 1 ? 's' : ''} na temporada!` : 'Fim da temporada'}</h2>
        </div>
      </header>

      <div className="se-record">
        <span>
          <b>{season.matches}</b> jogos
        </span>
        <span className="w">
          <b>{season.wins}</b> V
        </span>
        <span className="d">
          <b>{season.draws}</b> E
        </span>
        <span className="l">
          <b>{season.losses}</b> D
        </span>
      </div>

      <ul className="se-comps">
        {comps.map((c) => (
          <li key={c.competition}>
            <CompEmblem comp={c.competition} size={26} />
            <span>
              <b>{COMP_NAME[c.competition]}</b>
              <small>
                Campeão: <ClubCrest clubId={c.champion} size={14} /> {getClubById(c.champion)?.name}
              </small>
            </span>
            {c.player_result && <em className={c.player_result === 'Campeão' ? 'is-gold' : ''}>{c.player_result}</em>}
          </li>
        ))}
      </ul>

      {objectives.length > 0 && (
        <ul className="se-objs">
          {objectives.map((o) => (
            <li key={o.id} className={`is-${o.status}`}>
              {o.status === 'met' ? <CircleCheck size={15} /> : <CircleX size={15} />} {o.label}
            </li>
          ))}
        </ul>
      )}

      {coach.status === 'unemployed' ? (
        <p className="se-note">Você está sem clube. As propostas aparecem na aba Carreira — dá para começar a próxima temporada e esperar por elas.</p>
      ) : (
        <p className="se-note">
          Você segue no cargo: <ClubCrest clubId={coach.club_id} size={14} /> <b>{getClubById(coach.club_id)?.name}</b>. O calendário segue e a diretoria renova os objetivos.
        </p>
      )}

      {nextStartsOn && <p className="se-note">A próxima temporada começa em {new Date(`${nextStartsOn}T12:00:00Z`).toLocaleDateString('pt-BR', { timeZone: 'UTC' })}. O calendário avança automaticamente até essa data.</p>}
      <div className="se-actions">
        {offers > 0 && (
          <button type="button" className="gx-btn-ghost" onClick={onOffers}>
            <ArrowLeftRight size={16} /> {offers} proposta{offers > 1 ? 's' : ''}
          </button>
        )}
        <button type="button" className="gx-btn" disabled={starting || !!nextStartsOn} onClick={onStartNext}>
          {starting ? <span className="nm-spin" /> : <Play size={18} fill="currentColor" />} {nextStartsOn ? 'Preparando a próxima temporada…' : 'Começar a próxima temporada'}
        </button>
      </div>
    </section>
  )
}
