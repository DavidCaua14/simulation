import { useEffect, useState } from 'react'
import { X } from 'lucide-react'
import ProfileHero from '../profile/components/ProfileHero'
import BadgeGrid from '../profile/components/BadgeGrid'
import CardView from '../cards/components/CardView'
import { tierOf, TIER_ORDER } from '../cards/data/tiers'
import { getClubById } from '../club/data/clubs'
import { fetchCompetitions } from '../seasons/services/managerApi'
import { fetchFriendProfile } from './friendsApi'
import '../cards/cards.css'
import '../profile/profile.css'
import { Skeleton } from '../../components/ui/feedback'

// Perfil de um amigo: SOMENTE LEITURA (o servidor só devolve o que o dono deixou público).
export default function FriendProfile({ username, onClose, onRemove }) {
  const [p, setP] = useState(null)
  const [error, setError] = useState('')
  const [comps, setComps] = useState({})
  useEffect(() => {
    fetchFriendProfile(username).then(setP).catch((e) => setError(e.message))
    fetchCompetitions().then((l) => setComps(Object.fromEntries((l || []).map((c) => [c.id, c])))).catch(() => {})
  }, [username])

  return (
    <div className="fr-profile" role="dialog" aria-modal="true" aria-label={`Perfil de ${username}`}>
      <button type="button" className="fr-close" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
      <div className="fr-profile-scroll">
        {error && <p className="pf-error" style={{ padding: 20 }}>{error}</p>}
        {!p && !error && <div style={{ padding: 14 }}><Skeleton rows={1} variant="tall" /><div style={{ height: 10 }} /><Skeleton rows={3} variant="line" /></div>}
        {p && (
          <>
            <ProfileHero profile={p} />
            {p.friend_since && <p className="fr-since">Amigos desde {new Date(p.friend_since).toLocaleDateString('pt-BR')}</p>}
            {p.featured_card && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Carta em destaque</h2></header>
                <div className="pf-featured-body" style={{ '--tier': tierOf(p.featured_card.tier).color }}>
                  <CardView card={p.featured_card} width={130} shine />
                  <div><strong>{p.featured_card.name}</strong><span>{tierOf(p.featured_card.tier).label} · nota {p.featured_card.overall}</span></div>
                </div>
              </section>
            )}
            <section className="pf-panel">
              <header className="pf-panel-head"><h2>Insígnias</h2><span className="pf-count">{p.badges?.length || 0}</span></header>
              <BadgeGrid badges={p.badges} showLocked={false} />
            </section>
            {p.stats && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Carreira de treinador</h2></header>
                <dl className="pf-stats six">
                  <div><dt>Jogos</dt><dd>{p.stats.matches}</dd></div>
                  <div><dt>Vitórias</dt><dd>{p.stats.wins}</dd></div>
                  <div><dt>Empates</dt><dd>{p.stats.draws}</dd></div>
                  <div><dt>Derrotas</dt><dd>{p.stats.losses}</dd></div>
                  <div><dt>Gols</dt><dd>{p.stats.gf}–{p.stats.ga}</dd></div>
                  <div><dt>Temporadas</dt><dd>{p.stats.seasons}</dd></div>
                </dl>
              </section>
            )}
            {p.titles && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Títulos</h2><span className="pf-count">{p.titles.length}</span></header>
                {p.titles.length === 0 ? <p className="pf-hint">Nenhum título ainda.</p> : (
                  <ul className="pf-titles">
                    {p.titles.map((t, i) => (
                      <li key={i}><span className="pf-trophy" aria-hidden="true">🏆</span>
                        <span><strong>{comps[t.competition]?.name || t.competition}</strong><small>{t.year} · {getClubById(t.club_id)?.name || t.club_id}</small></span></li>
                    ))}
                  </ul>
                )}
              </section>
            )}
            {p.collection && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Coleção</h2></header>
                <p className="pf-hint">{p.collection.owned} de {p.collection.total} cartas</p>
                <div className="pf-col-bars">
                  {TIER_ORDER.slice().reverse().map((t) => (
                    <div key={t} style={{ '--tier': tierOf(t).color }}><span>{tierOf(t).label}</span><b>{p.collection.by_tier?.[t] || 0}</b></div>
                  ))}
                </div>
              </section>
            )}
            {!p.stats && !p.titles && !p.collection && <p className="pf-hint" style={{ padding: '12px 16px' }}>{p.nickname} preferiu deixar carreira, títulos e coleção privados.</p>}
            {onRemove && p.friendship_id && (
              <button type="button" className="pf-btn danger block fr-remove" onClick={() => onRemove(p.friendship_id)}>Desfazer amizade</button>
            )}
          </>
        )}
      </div>
    </div>
  )
}
