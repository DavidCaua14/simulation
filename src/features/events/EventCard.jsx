import { Check, Clock, Gift, Hourglass, Lock, RotateCw } from 'lucide-react'
import { BANNER_ICONS, CATEGORY_LABEL, RewardChip, fmtDate, timeLeft } from './eventsUi'

// Um evento: faixa com nome/categoria/tempo, objetivos com barra de progresso, recompensas e o botão de resgate.
export default function EventCard({ ev, now, busy, onClaim, playerLevel }) {
  const Icon = BANNER_ICONS[ev.banner?.icon] || Gift
  const comp = ev.completion
  const done = ev.objectives.every((o) => o.progress >= o.target)
  const lockedLevel = playerLevel != null && playerLevel < ev.min_level
  const limitReached = ev.max_completions && ev.completions_total >= ev.max_completions && !comp

  let when
  if (ev.state === 'scheduled') when = <><Clock size={12} /> começa em {timeLeft(ev.starts_at, now)}</>
  else if (ev.state === 'ended') when = <><Hourglass size={12} /> encerrado em {fmtDate(ev.ends_at)}</>
  else if (ev.recurrence !== 'none') when = <><RotateCw size={12} /> renova em {timeLeft(ev.period_end, now)}</>
  else when = <><Hourglass size={12} /> termina em {timeLeft(ev.ends_at, now)}</>

  return (
    <article className={`ev-card is-${ev.state} ${comp?.claimable ? 'is-claimable' : ''}`}>
      <header className="ev-banner" style={{ backgroundImage: ev.banner?.css || 'linear-gradient(135deg,#1d2b4a,#3a5bd0)' }}>
        <span className="ev-banner-icon"><Icon size={22} /></span>
        <span className="ev-banner-main">
          <small>{CATEGORY_LABEL[ev.category] || ev.category}{ev.min_level > 1 ? ` · nível ${ev.min_level}+` : ''}</small>
          <strong>{ev.name}</strong>
        </span>
        <span className="ev-when">{when}</span>
        {comp?.claimable && <span className="ev-ribbon"><Gift size={11} /> Recompensa pronta</span>}
        {ev.state === 'scheduled' && <span className="ev-ribbon is-soon">Começa {fmtDate(ev.starts_at)}</span>}
      </header>

      <div className="ev-body">
        <p className="ev-desc">{ev.description}</p>
        <ul className="ev-objs">
          {ev.objectives.map((o) => {
            const pct = Math.min(100, Math.round((o.progress / o.target) * 100))
            const ok = o.progress >= o.target
            return (
              <li key={o.id} className={ok ? 'is-ok' : ''}>
                <span className="ev-obj-row">
                  <span>{ok && <Check size={13} />} {o.label}</span>
                  <b>{Math.min(o.progress, o.target)}/{o.target}</b>
                </span>
                <span className="ev-bar" role="progressbar" aria-valuemin={0} aria-valuemax={o.target} aria-valuenow={o.progress}>
                  <i style={{ width: `${pct}%` }} />
                </span>
              </li>
            )
          })}
        </ul>

        <div className="ev-rewards">
          <span className="ev-rewards-label">Recompensa</span>
          <div className="ev-chips">{ev.rewards.map((r, i) => <RewardChip key={i} r={r} />)}</div>
        </div>

        {comp?.claimable && (
          <button type="button" className="gx-btn ev-claim" disabled={busy} onClick={() => onClaim(ev, comp.id)} data-sfx="select">
            <Gift size={16} /> {busy ? 'Resgatando…' : 'Resgatar'}
          </button>
        )}
        {comp?.claimable && <p className="ev-note">Resgate até {fmtDate(comp.claim_until)}.</p>}
        {comp?.claimed_at && <p className="ev-done"><Check size={14} /> Recompensa resgatada{ev.recurrence !== 'none' ? ' — volte no próximo período!' : '.'}</p>}
        {comp && !comp.claimable && !comp.claimed_at && <p className="ev-note">O prazo de resgate terminou.</p>}
        {!comp && ev.state === 'active' && lockedLevel && <p className="ev-note"><Lock size={12} /> Disponível a partir do nível {ev.min_level}.</p>}
        {!comp && limitReached && <p className="ev-done"><Check size={14} /> Você já completou este evento.</p>}
        {!comp && ev.state === 'active' && !done && !lockedLevel && !limitReached && (
          <p className="ev-note">O progresso conta sozinho enquanto você joga.</p>
        )}
      </div>
    </article>
  )
}
