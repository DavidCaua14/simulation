import { Check, Coins, Flame, Gem } from 'lucide-react'
import { tierOf } from '../cards/data/tiers'
import { timeLeft } from './eventsUi'

// Sequência diária: 7 dias de recompensas crescentes. Libera com uma partida concluída ou um palpite no dia
// (horário de Brasília). Pular um dia recomeça do dia 1.
export default function StreakPanel({ streak, now, busy, onClaim }) {
  if (!streak?.active) return null
  const { current, best, claimed_today: claimed, eligible_today: eligible, today_day: today, rewards = [] } = streak
  return (
    <section className="ev-streak" aria-label="Sequência diária">
      <header className="ev-streak-head">
        <span className="ev-streak-flame"><Flame size={20} /></span>
        <span>
          <strong>Sequência diária</strong>
          <small>{current > 0 ? `${current} ${current === 1 ? 'dia seguido' : 'dias seguidos'}` : 'Comece hoje'} · recorde {best}</small>
        </span>
        <small className="ev-streak-reset">vira em {timeLeft(streak.resets_at, now)}</small>
      </header>
      <ol className="ev-days">
        {rewards.map((r) => {
          const past = claimed ? r.day <= today : r.day < today
          const isToday = r.day === today
          return (
            <li key={r.day} className={`${past ? 'is-past' : ''} ${isToday ? 'is-today' : ''}`}>
              <small>Dia {r.day}</small>
              {past ? <Check size={16} /> : r.box_tier ? <img src={tierOf(r.box_tier)?.closed} alt={`caixa ${r.box_tier}`} /> : r.diamonds > 0 ? <Gem size={16} className="ev-ic-gems" /> : <Coins size={16} className="ev-ic-coins" />}
              <b>{r.coins}</b>
              {r.diamonds > 0 && <i>+{r.diamonds}<Gem size={9} /></i>}
            </li>
          )
        })}
      </ol>
      {claimed ? (
        <p className="ev-done"><Check size={14} /> Recompensa de hoje resgatada. Volte amanhã para o dia {(today % streak.cycle_days) + 1}.</p>
      ) : eligible ? (
        <button type="button" className="gx-btn ev-claim" disabled={busy} onClick={onClaim} data-sfx="select">
          <Flame size={16} /> {busy ? 'Resgatando…' : `Resgatar dia ${today}`}
        </button>
      ) : (
        <p className="ev-note">Jogue uma partida em Temporadas ou faça um palpite hoje para liberar a recompensa do dia {today}.</p>
      )}
    </section>
  )
}
