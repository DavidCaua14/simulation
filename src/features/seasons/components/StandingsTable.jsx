import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'

// Zonas coloridas: no Brasileirão (20 clubes) G4 / G6 / Z4; nos grupos, os 2 primeiros avançam.
function zoneOf(mode, pos, total) {
  if (mode === 'group') return pos <= 2 ? 'qual' : ''
  if (pos <= 4) return 'g4'
  if (pos <= 6) return 'g6'
  if (pos > total - 4) return 'z4'
  return ''
}

export default function StandingsTable({ rows, myClub, mode = 'league' }) {
  if (!rows?.length) return <p className="sn-muted">Sem dados ainda.</p>
  return (
    <div className="sn-table-wrap">
      <table className="sn-table">
        <thead>
          <tr>
            <th>#</th>
            <th className="left">Clube</th>
            <th title="Pontos">P</th>
            <th title="Jogos">J</th>
            <th title="Vitórias">V</th>
            <th title="Empates">E</th>
            <th title="Derrotas">D</th>
            <th title="Saldo de gols">SG</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.club_id} className={`${r.club_id === myClub ? 'is-mine' : ''} zone-${zoneOf(mode, r.pos, rows.length)}`}>
              <td className="pos">{r.pos}</td>
              <td className="left club">
                <ClubCrest clubId={r.club_id} size={20} />
                <span>{getClubById(r.club_id)?.name}</span>
              </td>
              <td className="pts">{r.points}</td>
              <td>{r.played}</td>
              <td>{r.wins}</td>
              <td>{r.draws}</td>
              <td>{r.losses}</td>
              <td>{r.gd > 0 ? `+${r.gd}` : r.gd}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="sn-legend">
        {mode === 'group' ? (
          <span>
            <i className="dot qual" /> Avançam às oitavas
          </span>
        ) : (
          <>
            <span>
              <i className="dot g4" /> Libertadores (G4)
            </span>
            <span>
              <i className="dot g6" /> Pré-Libertadores
            </span>
            <span>
              <i className="dot z4" /> Rebaixamento
            </span>
          </>
        )}
      </p>
    </div>
  )
}
