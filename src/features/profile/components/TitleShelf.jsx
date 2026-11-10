import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../../seasons/ui/CompEmblem'
import { COMP_NAME, COMP_SHORT, COMP_THEME } from '../../seasons/utils/seasonUtils'

const STREAK = { 2: 'Bicampeão', 3: 'Tricampeão', 4: 'Tetracampeão', 5: 'Pentacampeão', 6: 'Hexacampeão' }
const SEASON_FEAT = { 2: 'Dobradinha', 3: 'Tríplice coroa', 4: 'Quádrupla coroa' }

// Maior sequência de anos seguidos numa lista de anos.
function longestRun(years) {
  const ys = [...new Set(years)].sort((a, b) => a - b)
  let best = 0
  let run = 0
  ys.forEach((y, i) => {
    run = i > 0 && y === ys[i - 1] + 1 ? run + 1 : 1
    best = Math.max(best, run)
  })
  return best
}

// Sala de troféus (meu perfil e perfil de amigos): uma vitrine por campeonato, com o emblema oficial,
// quantas vezes foi conquistado e em que anos; abaixo, a linha do tempo das temporadas campeãs.
// `titles` = [{ competition, year, club_id }] (vem do servidor); `comps` = mapa id -> campeonato.
export default function TitleShelf({ titles = [], comps = {} }) {
  if (!titles.length) return null
  const nameOf = (id) => comps[id]?.name || COMP_NAME[id] || id
  const shortOf = (id) => comps[id]?.short_name || COMP_SHORT[id] || nameOf(id)
  const themeOf = (id) => comps[id]?.theme || COMP_THEME[id] || null

  const byComp = Object.values(
    titles.reduce((acc, t) => {
      const g = (acc[t.competition] ||= { id: t.competition, years: [] })
      g.years.push(t.year)
      return acc
    }, {}),
  )
    .map((g) => ({ ...g, years: g.years.sort((a, b) => a - b), run: longestRun(g.years) }))
    .sort((a, b) => b.years.length - a.years.length || nameOf(a.id).localeCompare(nameOf(b.id), 'pt-BR'))

  const order = byComp.map((g) => g.id) // mesma ordem da vitrine nas temporadas
  const byYear = Object.values(
    titles.reduce((acc, t) => {
      const g = (acc[t.year] ||= { year: t.year, items: [] })
      g.items.push(t)
      return acc
    }, {}),
  )
    .map((s) => ({ ...s, items: s.items.sort((a, b) => order.indexOf(a.competition) - order.indexOf(b.competition)) }))
    .sort((a, b) => b.year - a.year)

  const best = byYear.reduce((m, s) => (s.items.length > m.items.length ? s : m), byYear[0])

  return (
    <div className="ts">
      <dl className="ts-sum">
        <div className="is-gold"><dd>{titles.length}</dd><dt>Título{titles.length === 1 ? '' : 's'}</dt></div>
        <div><dd>{byYear.length}</dd><dt>Temporada{byYear.length === 1 ? '' : 's'} campeã{byYear.length === 1 ? '' : 's'}</dt></div>
        <div><dd>{best.year}</dd><dt>Melhor ano · {best.items.length} taça{best.items.length === 1 ? '' : 's'}</dt></div>
      </dl>

      <ul className="ts-cab">
        {byComp.map((g) => {
          const theme = themeOf(g.id)
          const n = g.years.length
          return (
            <li key={g.id} style={{ '--ts-accent': theme?.c1 || '#3d7bea' }} aria-label={`${nameOf(g.id)}: ${n} título${n === 1 ? '' : 's'} (${g.years.join(', ')})`}>
              <span className="ts-x" aria-hidden="true">{n}×</span>
              <span className="ts-stand" aria-hidden="true"><CompEmblem comp={g.id} size={50} theme={theme} /></span>
              <strong>{shortOf(g.id)}</strong>
              <small>{g.years.join(' · ')}</small>
              {g.run >= 2 && <em>{STREAK[g.run] || `${g.run} seguidos`}</em>}
            </li>
          )
        })}
      </ul>

      <h3 className="ts-sub">Temporadas campeãs</h3>
      <ol className="ts-line">
        {byYear.map((s) => {
          const clubs = [...new Set(s.items.map((t) => t.club_id).filter(Boolean))]
          const feat = SEASON_FEAT[Math.min(s.items.length, 4)]
          return (
            <li key={s.year} className={feat ? 'is-feat' : ''}>
              <b className="ts-year">{s.year}</b>
              <span className="ts-club">
                {clubs.map((c) => <ClubCrest key={c} clubId={c} size={22} />)}
                <span>{clubs.map((c) => getClubById(c)?.name || c).join(' / ')}</span>
                {feat && <em>{feat}</em>}
              </span>
              <span className="ts-cups">
                {s.items.map((t, i) => (
                  <span key={`${t.competition}-${i}`} title={nameOf(t.competition)}>
                    <CompEmblem comp={t.competition} size={26} theme={themeOf(t.competition)} />
                  </span>
                ))}
              </span>
            </li>
          )
        })}
      </ol>
    </div>
  )
}
