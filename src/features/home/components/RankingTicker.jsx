import { RankingIcon } from '../../../components/ui/icons'
import { RANKING_PREVIEW } from '../data/rankingPreview'

function Entries({ hidden }) {
  return (
    <div className="ranking-ticker-list" aria-hidden={hidden || undefined}>
      {RANKING_PREVIEW.map((entry) => (
        <span className="ranking-entry" key={entry.position}>
          <span className="ranking-entry-pos">#{entry.position}</span>
          <strong>{entry.nickname}</strong>
          <span className="ranking-entry-pts">{entry.points.toLocaleString('pt-BR')} pts</span>
        </span>
      ))}
    </div>
  )
}

export default function RankingTicker() {
  return (
    <div className="ranking-ticker">
      <span className="ranking-ticker-label">
        <RankingIcon size={13} />
        Ranking
      </span>
      <div className="ranking-ticker-track">
        <div className="ranking-ticker-inner">
          <Entries />
          <Entries hidden />
        </div>
      </div>
    </div>
  )
}
