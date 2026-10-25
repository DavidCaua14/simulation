import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { involves } from '../utils/seasonSelectors'

// "Jogos da rodada": todos os placares de uma rodada, seu jogo em destaque.
// Aceita jogos crus do banco (home_club/home_goals...) ou do retorno do season_play (home/hg...).
const norm = (m) => ({
  id: m.id ?? `${m.home ?? m.home_club}-${m.away ?? m.away_club}`,
  home: m.home_club ?? m.home,
  away: m.away_club ?? m.away,
  hg: m.home_goals ?? m.hg ?? null,
  ag: m.away_goals ?? m.ag ?? null,
  hp: m.home_pens ?? m.hp ?? null,
  ap: m.away_pens ?? m.ap ?? null,
  fid: typeof m.id === 'number' ? m.id : null,
  group: m.group_label ?? m.group ?? null,
  mine: !!m.mine,
})

function Line({ m, myClub, onOpen }) {
  const mine = m.mine || involves({ home_club: m.home, away_club: m.away }, myClub)
  const played = m.hg != null && m.ag != null
  const open = onOpen && played && m.fid ? () => onOpen(m.fid) : undefined
  return (
    <li className={`sn-rr-line ${mine ? 'is-mine' : ''} ${open ? 'is-link' : ''}`} onClick={open} role={open ? 'button' : undefined} tabIndex={open ? 0 : undefined}>
      <span className="home">
        <b>{getClubById(m.home)?.name}</b>
        <ClubCrest clubId={m.home} size={20} />
      </span>
      <span className="score">
        {played ? `${m.hg} × ${m.ag}` : '–  ×  –'}
        {played && m.hp != null && <small>pên. {m.hp}–{m.ap}</small>}
      </span>
      <span className="away">
        <ClubCrest clubId={m.away} size={20} />
        <b>{getClubById(m.away)?.name}</b>
      </span>
    </li>
  )
}

export default function RoundResults({ matches = [], myClub, title, onOpen }) {
  const list = matches.map(norm)
  const groups = [...new Set(list.map((m) => m.group).filter(Boolean))].sort()
  return (
    <section className="sn-rr">
      {title && <h4 className="sn-rr-title">{title}</h4>}
      {groups.length ? (
        groups.map((g) => (
          <div key={g}>
            <h5 className="sn-rr-sub">Grupo {g}</h5>
            <ul>
              {list
                .filter((m) => m.group === g)
                .map((m) => (
                  <Line key={m.id} m={m} myClub={myClub} onOpen={onOpen} />
                ))}
            </ul>
          </div>
        ))
      ) : (
        <ul>
          {list.map((m) => (
            <Line key={m.id} m={m} myClub={myClub} onOpen={onOpen} />
          ))}
        </ul>
      )}
    </section>
  )
}
