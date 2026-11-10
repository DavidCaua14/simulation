// Ficha do treinador: reputação, aproveitamento, campanha e gols. Usada no meu perfil e no perfil de amigos.
export default function CoachCard({ stats, titles = 0 }) {
  if (!stats) return null
  const m = stats.matches || 0
  const pct = (n) => (m > 0 ? (n / m) * 100 : 0)
  const success = m > 0 ? Math.round(((stats.wins * 3 + stats.draws) / (m * 3)) * 100) : 0
  const diff = (stats.gf || 0) - (stats.ga || 0)
  const rep = Math.max(0, Math.min(100, stats.reputation ?? 0))
  return (
    <div className="pf-coach">
      <div className="pf-kpis">
        <div>
          <small>Reputação</small>
          <b>{Math.round(rep)}</b>
          <span className="pf-meter" aria-hidden="true"><i style={{ width: `${rep}%` }} /></span>
        </div>
        <div>
          <small>Aproveitamento</small>
          <b>{success}%</b>
          <span className="pf-meter" aria-hidden="true"><i style={{ width: `${success}%` }} /></span>
        </div>
        <div>
          <small>Títulos</small>
          <b>{titles}</b>
          <span className="pf-kpi-note">{stats.seasons || 0} temporada{stats.seasons === 1 ? '' : 's'}</span>
        </div>
      </div>

      <div className="pf-record" role="img" aria-label={`${stats.wins} vitórias, ${stats.draws} empates e ${stats.losses} derrotas em ${m} jogos`}>
        {m > 0 ? (
          <>
            <i className="w" style={{ width: `${pct(stats.wins)}%` }} />
            <i className="d" style={{ width: `${pct(stats.draws)}%` }} />
            <i className="l" style={{ width: `${pct(stats.losses)}%` }} />
          </>
        ) : <i className="d" style={{ width: '100%' }} />}
      </div>
      <ul className="pf-record-legend">
        <li className="w"><b>{stats.wins}</b> Vitórias</li>
        <li className="d"><b>{stats.draws}</b> Empates</li>
        <li className="l"><b>{stats.losses}</b> Derrotas</li>
      </ul>

      <dl className="pf-facts">
        <div><dt>Jogos</dt><dd>{m}</dd></div>
        <div><dt>Gols</dt><dd>{stats.gf}</dd></div>
        <div><dt>Sofridos</dt><dd>{stats.ga}</dd></div>
        <div><dt>Saldo</dt><dd className={diff > 0 ? 'pos' : diff < 0 ? 'neg' : ''}>{diff > 0 ? `+${diff}` : diff}</dd></div>
      </dl>
    </div>
  )
}
