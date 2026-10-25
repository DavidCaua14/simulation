import ClubCrest from '../../club/components/ClubCrest'

const ROWS = [
  ['poss', 'Posse de bola', '%'],
  ['shots', 'Finalizações'],
  ['sot', 'No gol'],
  ['saves', 'Defesas do goleiro'],
  ['corners', 'Escanteios'],
  ['fouls', 'Faltas'],
  ['offsides', 'Impedimentos'],
  ['yellows', 'Amarelos'],
  ['reds', 'Vermelhos'],
]

// Estatísticas da partida em barras espelhadas (mandante à esquerda)
export default function MatchStats({ stats, home, away }) {
  if (!stats) return <p className="sn-muted sn-center">Estatísticas indisponíveis para este jogo.</p>
  return (
    <div className="ml-stats">
      <div className="ml-stat-head">
        <ClubCrest clubId={home} size={22} />
        <span />
        <ClubCrest clubId={away} size={22} />
      </div>
      {ROWS.filter(([k]) => Array.isArray(stats[k])).map(([k, label, suf = '']) => {
        const h = Number(stats[k][0]) || 0
        const a = Number(stats[k][1]) || 0
        return (
          <div key={k} className="ml-stat">
            <b className={h > a ? 'lead' : ''}>
              {h}
              {suf}
            </b>
            <span>
              <small>{label}</small>
              <i>
                <em className="h" style={{ width: `${h + a ? (h / (h + a)) * 100 : 50}%` }} />
              </i>
            </span>
            <b className={a > h ? 'lead' : ''}>
              {a}
              {suf}
            </b>
          </div>
        )
      })}
    </div>
  )
}
