import { Coins, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { COMP_NAME, fmt } from '../utils/seasonUtils'

// Fim de temporada: campeões, sua campanha em cada torneio, o que você ganhou e o botão da próxima.
export default function SeasonSummary({ season, starting, onStartNext }) {
  const summary = season.summary || []
  const titles = summary.filter((s) => s.player_result === 'Campeão').length
  return (
    <section className="ss">
      <div className="ss-head">
        <span className="ss-trophy" aria-hidden="true">
          <Trophy size={34} />
        </span>
        <small>Fim de temporada</small>
        <h2>Temporada {season.year}</h2>
        <p>
          {season.matches} jogos · {season.wins}V {season.draws}E {season.losses}D · {season.goals} gols · {season.assists} assist.
        </p>
        {titles > 0 && <span className="gx-tag is-gold">{titles} título{titles > 1 ? 's' : ''} conquistado{titles > 1 ? 's' : ''}!</span>}
      </div>

      <ul className="ss-list">
        {summary.map((s) => (
          <li key={s.competition} className={s.player_result === 'Campeão' ? 'is-title' : ''}>
            <CompEmblem comp={s.competition} size={30} />
            <div>
              <b>{COMP_NAME[s.competition]}</b>
              <span>
                Campeão: {s.champion && <ClubCrest clubId={s.champion} size={16} />} {getClubById(s.champion)?.name}
              </span>
              {s.player_result && (
                <span className="mine">
                  Sua campanha: <b>{s.player_result}</b>
                  {s.bonus_xp > 0 ? ` · +${fmt(s.bonus_xp)} XP · +${fmt(s.bonus_coins)} moedas` : ''}
                </span>
              )}
            </div>
          </li>
        ))}
      </ul>

      <div className="ss-earn">
        <span>
          <b>+{fmt(season.xp_earned)}</b> XP
        </span>
        <span>
          <Coins size={14} /> <b>+{fmt(season.coins_earned)}</b> moedas
        </span>
      </div>
      <p className="sn-hint">Veja o Mercado: clubes podem ter se interessado em você.</p>
      <button type="button" className="gx-btn" disabled={starting} onClick={onStartNext}>
        {starting ? 'Preparando…' : `Iniciar temporada ${season.year + 1}`}
      </button>
    </section>
  )
}
