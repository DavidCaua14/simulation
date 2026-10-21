import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { STAGE_LABEL } from '../utils/seasonUtils'

const KNOCKOUT = ['r16', 'qf', 'sf', 'final']

// Agrupa os jogos de mata-mata em confrontos (ida + volta somados).
function buildTies(fixtures) {
  const ties = {}
  for (const f of fixtures) {
    if (!KNOCKOUT.includes(f.stage)) continue
    const key = `${f.stage}:${f.tie_no}`
    ;(ties[key] ||= { stage: f.stage, tie: f.tie_no, legs: [] }).legs.push(f)
  }
  return Object.values(ties).map((t) => {
    const legs = [...t.legs].sort((a, b) => a.leg - b.leg)
    const a = legs[0].home_club
    const b = legs[0].away_club
    let ga = 0
    let gb = 0
    for (const l of legs) {
      if (l.status !== 'played') continue
      ga += l.home_club === a ? l.home_goals : l.away_goals
      gb += l.home_club === b ? l.home_goals : l.away_goals
    }
    const last = legs[legs.length - 1]
    const pens =
      last.home_pens != null ? (last.home_club === a ? `${last.home_pens}–${last.away_pens}` : `${last.away_pens}–${last.home_pens}`) : null
    return { ...t, legs, a, b, ga, gb, winner: last.tie_winner, pens, started: legs.some((l) => l.status === 'played') }
  })
}

function Line({ club, goals, win, mine, started }) {
  return (
    <div className={`sn-tie-line ${win ? 'is-win' : ''} ${mine ? 'is-mine' : ''}`}>
      <ClubCrest clubId={club} size={22} />
      <span>{getClubById(club)?.name}</span>
      <b>{started ? goals : '–'}</b>
    </div>
  )
}

export default function Bracket({ fixtures, myClub }) {
  const ties = buildTies(fixtures)
  if (!ties.length) return <p className="sn-muted">O mata-mata ainda não começou.</p>

  return (
    <div className="sn-bracket">
      {KNOCKOUT.filter((s) => ties.some((t) => t.stage === s)).map((stage) => (
        <section key={stage}>
          <h4 className="sn-bracket-title">{STAGE_LABEL[stage]}</h4>
          <div className="sn-ties">
            {ties
              .filter((t) => t.stage === stage)
              .sort((x, y) => x.tie - y.tie)
              .map((t) => (
                <div key={`${t.stage}-${t.tie}`} className="sn-tie card">
                  <Line club={t.a} goals={t.ga} win={t.winner === t.a} mine={t.a === myClub} started={t.started} />
                  <Line club={t.b} goals={t.gb} win={t.winner === t.b} mine={t.b === myClub} started={t.started} />
                  <small>
                    {t.legs
                      .filter((l) => l.status === 'played')
                      .map((l) => `${l.leg === 1 && stage !== 'final' ? 'Ida' : stage === 'final' ? 'Jogo' : 'Volta'} ${l.home_goals}×${l.away_goals}`)
                      .join(' · ') || 'A disputar'}
                    {t.pens ? ` · Pênaltis ${t.pens}` : ''}
                  </small>
                </div>
              ))}
          </div>
        </section>
      ))}
    </div>
  )
}
