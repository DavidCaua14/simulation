import { Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { fmt } from '../utils/seasonUtils'

const NAME = { brasileirao: 'Brasileirão Série A', copa_brasil: 'Copa do Brasil', libertadores: 'Copa Libertadores' }

// Mostrado quando a temporada termina: resultados e botão para começar a próxima.
export default function SeasonSummary({ season, starting, onStartNext }) {
  const summary = season.summary || []
  return (
    <section className="sn-summary card">
      <header>
        <Trophy size={22} />
        <div>
          <strong className="heading">Temporada {season.year} encerrada</strong>
          <small>
            {season.matches} jogos · {season.wins}V {season.draws}E {season.losses}D · {season.goals} gols · {season.assists} assist.
          </small>
        </div>
      </header>

      <ul>
        {summary.map((s) => (
          <li key={s.competition}>
            <b>{NAME[s.competition]}</b>
            <span>
              Campeão: {s.champion && <ClubCrest clubId={s.champion} size={16} />} {getClubById(s.champion)?.name}
            </span>
            {s.player_result && (
              <span className="mine">
                Sua campanha: {s.player_result}
                {s.bonus_xp > 0 ? ` · +${fmt(s.bonus_xp)} XP · +${fmt(s.bonus_coins)} moedas` : ''}
              </span>
            )}
          </li>
        ))}
      </ul>
      <p className="sn-hint">
        Nesta temporada você ganhou {fmt(season.xp_earned)} XP e {fmt(season.coins_earned)} moedas. Veja a aba Propostas: clubes podem ter se
        interessado em você.
      </p>
      <button type="button" className="btn-primary sn-continue" disabled={starting} onClick={onStartNext}>
        {starting ? 'Preparando…' : `Iniciar temporada ${season.year + 1}`}
      </button>
    </section>
  )
}
