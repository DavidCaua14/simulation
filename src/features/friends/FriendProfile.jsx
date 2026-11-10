import { useEffect, useState } from 'react'
import { Trophy, X } from 'lucide-react'
import ProfileHero from '../profile/components/ProfileHero'
import BadgeGrid from '../profile/components/BadgeGrid'
import CoachCard from '../profile/components/CoachCard'
import { getClubById } from '../club/data/clubs'
import { fetchCompetitions } from '../seasons/services/managerApi'
import { fetchFriendProfile } from './friendsApi'
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
            {p.stats && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Ficha do treinador</h2></header>
                <CoachCard stats={p.stats} titles={p.titles?.length ?? p.stats.titles ?? 0} />
              </section>
            )}
            {p.titles && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Sala de troféus</h2><span className="pf-count">{p.titles.length}</span></header>
                {p.titles.length === 0 ? <p className="pf-hint">Nenhum título conquistado ainda.</p> : (
                  <ul className="pf-titles">
                    {p.titles.map((t, i) => (
                      <li key={i}><span className="pf-trophy" aria-hidden="true"><Trophy size={18} /></span>
                        <span><strong>{comps[t.competition]?.name || t.competition}</strong><small>{t.year} · {getClubById(t.club_id)?.name || t.club_id}</small></span></li>
                    ))}
                  </ul>
                )}
              </section>
            )}
            <section className="pf-panel">
              <header className="pf-panel-head"><h2>Insígnias</h2><span className="pf-count">{p.badges?.length || 0}</span></header>
              <BadgeGrid badges={p.badges} showLocked={false} />
            </section>
            {!p.stats && !p.titles && <p className="pf-hint" style={{ padding: '12px 16px' }}>{p.nickname} preferiu manter a carreira e os títulos privados.</p>}
            {onRemove && p.friendship_id && (
              <button type="button" className="pf-btn danger block fr-remove" onClick={() => onRemove(p.friendship_id)}>Desfazer amizade</button>
            )}
          </>
        )}
      </div>
    </div>
  )
}
