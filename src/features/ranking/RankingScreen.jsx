import { useEffect, useState } from 'react'
import { ArrowLeft, Calculator, Crown, Trophy, X } from 'lucide-react'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import { avatarSrcOf } from '../profile/components/ProfileAvatar'
import { getClubById } from '../club/data/clubs'
import { breakdown, CRITERIA, fetchRanking, fetchRankingPhotos } from './rankingApi'
import './ranking.css'

// RANKING GERAL DOS TREINADORES: pódio, lista em ordem e a sua posição, com a pontuação explicada num modal.
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const clubName = (id) => (id ? getClubById(id)?.name || id : 'Sem clube')

// Avatar do jogador: foto enviada, foto pronta, avatar de lenda ou a foto da criação; sem nada, a inicial.
function Avatar({ e, photo, size }) {
  const src = photo || avatarSrcOf({ avatar: e.avatar, photo_id: e.photo_id })
  return (
    <span className="rk-av" style={{ '--size': `${size}px` }}>
      {src ? <img src={src} alt="" loading="lazy" /> : <b>{(e.nickname || '?').charAt(0).toUpperCase()}</b>}
    </span>
  )
}

function Line({ e, photo }) {
  return (
    <li className={`rk-row ${e.is_me ? 'is-me' : ''}`}>
      <b className="rk-pos">{e.position}</b>
      <Avatar e={e} photo={photo} size={36} />
      <span className="rk-who">
        <strong>{e.nickname}{e.is_me ? ' (você)' : ''}</strong>
        <small>Nível {e.level} · {clubName(e.club_id)} · {e.titles} {e.titles === 1 ? 'título' : 'títulos'}</small>
      </span>
      <span className="rk-pts"><b>{fmt(e.points)}</b><small>pts</small></span>
    </li>
  )
}

// Campanha no modo Temporadas: vitórias, empates e derrotas lado a lado, com barra proporcional.
function Campaign({ wins, draws, losses }) {
  const total = Math.max(1, wins + draws + losses)
  return (
    <div className="rk-camp">
      <div className="rk-camp-nums">
        <span className="w"><b>{wins}</b><small>vitórias</small></span>
        <span className="d"><b>{draws}</b><small>empates</small></span>
        <span className="l"><b>{losses}</b><small>derrotas</small></span>
      </div>
      <div className="rk-camp-bar" aria-hidden="true">
        <i className="w" style={{ width: `${(wins / total) * 100}%` }} />
        <i className="d" style={{ width: `${(draws / total) * 100}%` }} />
        <i className="l" style={{ width: `${(losses / total) * 100}%` }} />
      </div>
    </div>
  )
}

function ScoringModal({ me, onClose }) {
  const rows = me ? breakdown(me) : null
  return (
    <div className="rk-modal" role="dialog" aria-modal="true" aria-labelledby="rk-modal-title" onClick={onClose}>
      <div className="rk-modal-card" onClick={(ev) => ev.stopPropagation()}>
        <header>
          <h2 id="rk-modal-title"><Calculator size={18} /> Como funciona a pontuação</h2>
          <button type="button" className="rk-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
        </header>
        <ul className="rk-rules">{CRITERIA.map(([k, v]) => <li key={k}><b>{k}</b><span>{v}</span></li>)}</ul>
        {rows && (
          <>
            <h3>Seus pontos</h3>
            <table className="rk-break">
              <tbody>
                {rows.map(([k, how, pts]) => (
                  <tr key={k}><td>{k}<small>{how}</small></td><td className={pts < 0 ? 'neg' : ''}>{pts > 0 ? '+' : ''}{fmt(pts)}</td></tr>
                ))}
              </tbody>
              <tfoot><tr><td>Total</td><td>{fmt(me.points)}</td></tr></tfoot>
            </table>
          </>
        )}
        <p className="rk-note">Empate em pontos: vence quem tem mais nível, depois mais vitórias, depois quem se cadastrou primeiro.</p>
      </div>
    </div>
  )
}

export default function RankingScreen({ onBack }) {
  const [data, setData] = useState(null)
  const [photos, setPhotos] = useState({})
  const [error, setError] = useState('')
  const [howOpen, setHowOpen] = useState(false)
  useEffect(() => {
    fetchRanking(50).then((d) => {
      setData(d)
      if (d?.entries?.some((e) => e.has_photo)) fetchRankingPhotos(50).then(setPhotos)
    }).catch((e) => setError(e.message))
  }, [])

  const entries = data?.entries || []
  const podium = [entries[1], entries[0], entries[2]].filter(Boolean)
  const me = data?.me
  const photoOf = (e) => photos[String(e.position)]
  return (
    <div className="rk">
      <header className="rk-top">
        <button type="button" className="rk-back" onClick={onBack} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <h1>Ranking</h1>
        <button type="button" className="rk-how-btn" onClick={() => setHowOpen(true)}><Calculator size={16} /> Pontuação</button>
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
                <Avatar e={e} photo={photoOf(e)} size={e.position === 1 ? 72 : 58} />
                <strong>{e.nickname}</strong>
                <small>{fmt(e.points)} pts</small>
                <span className="rk-block"><b>{e.position}º</b></span>
              </div>
            ))}
          </section>

          {me && (
            <section className="rk-me" aria-label="Sua posição">
              <div className="rk-me-head">
                <Avatar e={me} photo={photoOf(me)} size={52} />
                <span className="rk-me-pos"><small>Sua posição</small><b>{me.position}º</b><em>de {fmt(data.total)}</em></span>
                <span className="rk-me-pts"><small>Pontos</small><b>{fmt(me.points)}</b></span>
              </div>
              <div className="rk-me-stats">
                <span><b>{me.level}</b><small>nível</small></span>
                <span><b>{me.titles}</b><small>títulos</small></span>
                <span><b>{String(me.reputation).replace('.', ',')}</b><small>reputação</small></span>
                <span><b>{me.events}</b><small>eventos</small></span>
              </div>
              <Campaign wins={me.wins} draws={me.draws} losses={me.losses} />
            </section>
          )}

          <ol className="rk-list" aria-label="Classificação">
            {entries.map((e) => <Line key={e.position} e={e} photo={photoOf(e)} />)}
          </ol>
        </>
      )}
      {howOpen && <ScoringModal me={me} onClose={() => setHowOpen(false)} />}
    </div>
  )
}
