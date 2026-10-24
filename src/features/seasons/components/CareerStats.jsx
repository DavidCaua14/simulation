import { Target, TrendingUp, Trophy, Users } from 'lucide-react'
import { fmt } from '../utils/seasonUtils'

// Anel de aproveitamento (vitórias / empates / derrotas) em SVG puro.
function Ring({ wins, draws, losses }) {
  const total = wins + draws + losses
  const r = 34
  const C = 2 * Math.PI * r
  const seg = (v) => (total ? (v / total) * C : 0)
  const parts = [
    { v: seg(wins), c: 'var(--gx-green)' },
    { v: seg(draws), c: 'var(--gx-gold)' },
    { v: seg(losses), c: 'var(--danger)' },
  ]
  let off = 0
  return (
    <svg className="cs-ring" viewBox="0 0 84 84" aria-hidden="true">
      <circle cx="42" cy="42" r={r} fill="none" stroke="var(--gx-line)" strokeWidth="9" />
      {parts.map((p, i) => {
        const el = (
          <circle key={i} cx="42" cy="42" r={r} fill="none" stroke={p.c} strokeWidth="9" strokeDasharray={`${p.v} ${C - p.v}`} strokeDashoffset={-off} transform="rotate(-90 42 42)" />
        )
        off += p.v
        return el
      })}
    </svg>
  )
}

// Desempenho da carreira: aproveitamento em destaque + números principais.
export default function CareerStats({ stats }) {
  const winRate = stats.matches ? Math.round((stats.wins / stats.matches) * 100) : 0
  const perGame = stats.matches ? ((stats.goals + stats.assists) / stats.matches).toFixed(2).replace('.', ',') : '0'
  return (
    <section className="cs gx-panel">
      <div className="cs-main">
        <div className="cs-ring-wrap">
          <Ring wins={stats.wins} draws={stats.draws} losses={stats.losses} />
          <span>
            <b>{winRate}%</b>
            <small>vitórias</small>
          </span>
        </div>
        <ul className="cs-wdl">
          <li className="w">
            <b>{fmt(stats.wins)}</b> vitórias
          </li>
          <li className="d">
            <b>{fmt(stats.draws)}</b> empates
          </li>
          <li className="l">
            <b>{fmt(stats.losses)}</b> derrotas
          </li>
          <li className="m">
            em <b>{fmt(stats.matches)}</b> jogos
          </li>
        </ul>
      </div>
      <div className="cs-grid">
        <div>
          <Target size={16} />
          <b>{fmt(stats.goals)}</b>
          <small>gols</small>
        </div>
        <div>
          <Users size={16} />
          <b>{fmt(stats.assists)}</b>
          <small>assistências</small>
        </div>
        <div>
          <TrendingUp size={16} />
          <b>{perGame}</b>
          <small>part. em gol/jogo</small>
        </div>
        <div className="gold">
          <Trophy size={16} />
          <b>{fmt(stats.titles)}</b>
          <small>títulos</small>
        </div>
      </div>
    </section>
  )
}
