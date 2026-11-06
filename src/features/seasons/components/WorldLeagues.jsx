import { useEffect, useState } from 'react'
import { ChevronLeft } from 'lucide-react'
import StandingsTable from './StandingsTable'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import CompEmblem from '../ui/CompEmblem'
import { fetchWorldLeagueTable, fetchWorldLeagues } from '../services/managerApi'

// Torneios > Ligas do mundo: todas as ligas e campeonatos do jogo, inclusive os que não estão acontecendo na sua carreira.
// Liga estrangeira sem jogos na sua carreira mostra a classificação calculada no banco (nada é gravado).
const COUNTRY = {
  BRA: 'Brasil', ARG: 'Argentina', URU: 'Uruguai', CHI: 'Chile', COL: 'Colômbia', ECU: 'Equador', PAR: 'Paraguai', PER: 'Peru',
  ENG: 'Inglaterra', ESP: 'Espanha', ITA: 'Itália', GER: 'Alemanha', FRA: 'França', POR: 'Portugal',
}
const KIND = { league: 'Liga', cup: 'Copa', continental: 'Continental' }

function LeagueDetail({ league, myClub, onBack }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  useEffect(() => {
    let alive = true
    fetchWorldLeagueTable(league.id)
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(e.message))
    return () => {
      alive = false
    }
  }, [league.id])

  return (
    <div className="wl">
      <button type="button" className="gx-btn-ghost wl-back" onClick={onBack}>
        <ChevronLeft size={16} /> Ligas do mundo
      </button>
      <section className="ct-banner" style={{ '--c1': league.theme?.c1 || '#333', '--c2': league.theme?.c2 || '#999' }}>
        <CompEmblem comp={league.id} size={58} theme={league.theme} />
        <div className="ct-banner-txt">
          <small>{[COUNTRY[league.country] || league.country, KIND[league.kind]].filter(Boolean).join(' · ')}</small>
          <h2>{league.name}</h2>
          <span className="ct-line">
            {league.in_season ? 'Acontecendo na sua temporada' : league.background ? 'Liga estrangeira · acompanhe e receba propostas' : 'Fora da sua temporada atual'}
          </span>
        </div>
      </section>
      {error && <p className="sn-muted sn-center">{error}</p>}
      {!data && !error && <div className="st-sk row" />}
      {data?.source === 'projection' && <p className="sn-hint">Classificação simulada até hoje no seu mundo. Ela passa a ter jogos de verdade se você assumir um clube desta liga.</p>}
      {data && data.rows.length > 0 && <StandingsTable rows={data.rows} myClub={myClub} zones={league.zones} />}
      {data && data.rows.length === 0 && (
        <ul className="wl-clubs">
          {data.clubs.map((c) => (
            <li key={c.club_id}>
              <ClubCrest clubId={c.club_id} size={22} />
              <span>{getClubById(c.club_id)?.name || c.club_id}</span>
              <small>Força {c.strength}</small>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default function WorldLeagues({ myClub, onClose }) {
  const [list, setList] = useState(null)
  const [error, setError] = useState(null)
  const [open, setOpen] = useState(null)
  useEffect(() => {
    let alive = true
    fetchWorldLeagues()
      .then((d) => alive && setList(d))
      .catch((e) => alive && setError(e.message))
    return () => {
      alive = false
    }
  }, [])

  if (open) return <LeagueDetail league={open} myClub={myClub} onBack={() => setOpen(null)} />
  const groups = []
  for (const l of list || []) {
    const key = l.kind === 'continental' ? 'Continentais' : COUNTRY[l.country] || l.country || 'Outros'
    let g = groups.find((x) => x.key === key)
    if (!g) groups.push((g = { key, items: [] }))
    g.items.push(l)
  }
  return (
    <div className="wl">
      <button type="button" className="gx-btn-ghost wl-back" onClick={onClose}>
        <ChevronLeft size={16} /> Minha temporada
      </button>
      {error && <p className="sn-muted sn-center">{error}</p>}
      {!list && !error && <div className="st-sk row" />}
      {groups.map((g) => (
        <section key={g.key} className="wl-group">
          <h3>{g.key}</h3>
          {g.items.map((l) => (
            <button key={l.id} type="button" className="wl-item" onClick={() => setOpen(l)}>
              <CompEmblem comp={l.id} size={30} theme={l.theme} />
              <span className="wl-txt">
                <b>{l.name}</b>
                <small>
                  {KIND[l.kind]} · {l.clubs} clubes
                </small>
              </span>
              {l.in_season && <span className="wl-badge">Na temporada</span>}
            </button>
          ))}
        </section>
      ))}
    </div>
  )
}
