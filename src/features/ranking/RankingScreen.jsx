import { useEffect, useState } from 'react'
import { ArrowLeft, ChevronDown, Crown, Trophy } from 'lucide-react'
import ClubCrest from '../club/components/ClubCrest'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import { getClubById } from '../club/data/clubs'
import { CRITERIA, fetchRanking } from './rankingApi'
import './ranking.css'

// RANKING GERAL DOS TREINADORES: pódio, lista em ordem e a sua posição, com os critérios explicados.
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const clubName = (id) => (id ? getClubById(id)?.name || id : 'Sem clube')

function Line({ e }) {
  return (
    <li className={`rk-row ${e.is_me ? 'is-me' : ''}`}>
      <b className="rk-pos">{e.position}</b>
      <span className="rk-crest">{e.club_id ? <ClubCrest clubId={e.club_id} size={26} /> : <Trophy size={18} />}</span>
      <span className="rk-who">
        <strong>{e.nickname}{e.is_me ? ' (você)' : ''}</strong>
        <small>Nível {e.level} · {clubName(e.club_id)} · {e.titles} {e.titles === 1 ? 'título' : 'títulos'} · {e.wins}V</small>
      </span>
      <span className="rk-pts"><b>{fmt(e.points)}</b><small>pts</small></span>
    </li>
  )
}

export default function RankingScreen({ onBack }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [howOpen, setHowOpen] = useState(false)
  useEffect(() => { fetchRanking(50).then(setData).catch((e) => setError(e.message)) }, [])

  const entries = data?.entries || []
  const podium = [entries[1], entries[0], entries[2]].filter(Boolean)
  const me = data?.me
  return (
    <div className="rk">
      <header className="rk-top">
        <button type="button" className="rk-back" onClick={onBack} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <h1>Ranking</h1>
        {data && <span className="rk-count">{fmt(data.total)} treinadores</span>}
      </header>
      {error && <Notice kind="error">{error}</Notice>}
      {!data && !error ? <Skeleton rows={6} /> : entries.length === 0 ? (
        <EmptyState icon={Trophy} title="Ranking vazio" text="Jogue partidas e evolua seu nível para aparecer aqui." />
      ) : data && (
        <>
          <section className="rk-podium" aria-label="Pódio">
            {podium.map((e) => (
              <div key={e.position} className={`rk-step p${e.position} ${e.is_me ? 'is-me' : ''}`}>
                {e.position === 1 && <Crown className="rk-crown" size={22} />}
                <span className="rk-badge">{e.club_id ? <ClubCrest clubId={e.club_id} size={40} /> : <Trophy size={26} />}</span>
                <strong>{e.nickname}</strong>
                <small>{fmt(e.points)} pts</small>
                <span className="rk-block"><b>{e.position}º</b></span>
              </div>
            ))}
          </section>

          {me && (
            <section className="rk-me" aria-label="Sua posição">
              <div className="rk-me-head">
                <span><small>Sua posição</small><b>{me.position}º</b></span>
                <span><small>Pontos</small><b>{fmt(me.points)}</b></span>
              </div>
              <div className="rk-me-stats">
                <span><b>{me.level}</b><small>nível</small></span>
                <span><b>{me.titles}</b><small>títulos</small></span>
                <span><b>{me.wins}-{me.draws}-{me.losses}</b><small>V-E-D</small></span>
                <span><b>{String(me.reputation).replace('.', ',')}</b><small>reputação</small></span>
                <span><b>{me.events}</b><small>eventos</small></span>
              </div>
            </section>
          )}

          <section className="rk-how">
            <button type="button" aria-expanded={howOpen} onClick={() => setHowOpen((v) => !v)}>
              Como os pontos são calculados <ChevronDown size={16} className={howOpen ? 'is-open' : ''} />
            </button>
            {howOpen && (
              <ul>{CRITERIA.map(([k, v]) => <li key={k}><b>{k}</b><span>{v}</span></li>)}</ul>
            )}
          </section>

          <ol className="rk-list" aria-label="Classificação">
            {entries.map((e) => <Line key={e.position} e={e} />)}
          </ol>
        </>
      )}
    </div>
  )
}
