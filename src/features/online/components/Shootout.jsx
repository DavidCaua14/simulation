import OnlineCrest from './OnlineCrest'
import { shootoutText } from '../shootoutText'
import './shootout.css'

// Painel da disputa: cobranças de cada lado (bolinhas), quem vai bater agora e o último resultado.
export default function Shootout({ events, home, away, mySide }) {
  const so = events.filter((e) => e.kind?.startsWith('so_'))
  if (!so.length) return null
  const kicks = { h: [], a: [] }
  for (const e of so) if (['so_goal', 'so_save', 'so_miss'].includes(e.kind)) kicks[e.side].push(e.kind === 'so_goal')
  const score = { h: kicks.h.filter(Boolean).length, a: kicks.a.filter(Boolean).length }
  const last = so.at(-1)
  const ready = last.kind === 'so_ready'
  const result = ['so_goal', 'so_save', 'so_miss'].includes(last.kind)
  const n = Math.max(5, kicks.h.length, kicks.a.length)
  const row = (s, club) => (
    <div className={`so-row ${s === mySide ? 'is-mine' : ''}`}>
      <OnlineCrest club={club} size={22} />
      <b>{club.short}</b>
      <span className="so-dots">
        {Array.from({ length: n }, (_, i) => <i key={i} className={kicks[s][i] == null ? '' : kicks[s][i] ? 'is-goal' : 'is-miss'} aria-label={kicks[s][i] == null ? 'a bater' : kicks[s][i] ? 'gol' : 'perdeu'} />)}
      </span>
      <em>{score[s]}</em>
    </div>
  )
  return (
    <section className={`so ${ready ? 'is-ready' : ''} ${result ? `is-${last.kind.slice(3)}` : ''}`} aria-live="polite" aria-label="Disputa de pênaltis">
      <h3>Disputa de pênaltis</h3>
      {row('h', home)}
      {row('a', away)}
      <p key={last.seq} className="so-call">
        {ready && <span className="so-ball" aria-hidden="true" />}
        {shootoutText(last)}
        {ready && String(last.detail || '').split('|')[1] && <small>Fôlego {String(last.detail).split('|')[1]}%</small>}
      </p>
    </section>
  )
}
