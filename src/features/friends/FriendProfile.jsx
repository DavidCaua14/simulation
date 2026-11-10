import { useEffect, useState } from 'react'
import { Trophy, UserMinus, Users, X } from 'lucide-react'
import ProfileHero from '../profile/components/ProfileHero'
import BadgeGrid from '../profile/components/BadgeGrid'
import CoachCard from '../profile/components/CoachCard'
import TitleShelf from '../profile/components/TitleShelf'
import { fetchCompetitions } from '../seasons/services/managerApi'
import { fetchFriendProfile } from './friendsApi'
import '../profile/profile.css'
import { Skeleton } from '../../components/ui/feedback'

const TIERS = [['ouro', 'Ouro'], ['prata', 'Prata'], ['bronze', 'Bronze']]

// Perfil de um amigo: SOMENTE LEITURA (o servidor só devolve o que o dono deixou público).
export default function FriendProfile({ username, onClose, onRemove }) {
  const [p, setP] = useState(null)
  const [error, setError] = useState('')
  const [comps, setComps] = useState({})
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    fetchFriendProfile(username).then(setP).catch((e) => setError(e.message))
    fetchCompetitions().then((l) => setComps(Object.fromEntries((l || []).map((c) => [c.id, c])))).catch(() => {})
  }, [username])

  const badges = (p?.badges || []).filter((b) => b.earned)
  const tiers = TIERS.map(([id, label]) => ({ id, label, n: badges.filter((b) => b.tier === id).length })).filter((t) => t.n > 0)

  return (
    <div className={`fr-profile ${scrolled ? 'is-scrolled' : ''}`} role="dialog" aria-modal="true" aria-label={`Perfil de ${username}`}>
      {/* barra fixa: aparece ao rolar, para o botão de fechar não ficar por cima do conteúdo */}
      <div className="fr-bar" aria-hidden={!scrolled}>
        <strong>{p?.nickname || username}</strong>
        {p && <span>NV {p.level ?? 1}</span>}
      </div>
      <button type="button" className="fr-close" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
      <div className="fr-profile-scroll" onScroll={(e) => setScrolled(e.currentTarget.scrollTop > 150)}>
        {error && <p className="pf-error" style={{ padding: 20 }}>{error}</p>}
        {!p && !error && <div style={{ padding: 14 }}><Skeleton rows={1} variant="tall" /><div style={{ height: 10 }} /><Skeleton rows={3} variant="line" /></div>}
        {p && (
          <>
            <ProfileHero profile={p} />
            {p.friend_since && (
              <p className="fr-since"><Users size={13} aria-hidden="true" /> Amigos desde {new Date(p.friend_since).toLocaleDateString('pt-BR')}</p>
            )}
            {p.titles && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2><Trophy size={15} aria-hidden="true" /> Sala de troféus</h2><span className="pf-count">{p.titles.length}</span></header>
                {p.titles.length === 0 ? (
                  <div className="pf-shelf-empty">
                    <Trophy size={30} aria-hidden="true" />
                    <p><b>Prateleira vazia</b>{p.nickname} ainda não conquistou nenhum título.</p>
                  </div>
                ) : <TitleShelf titles={p.titles} comps={comps} />}
              </section>
            )}
            {p.stats && (
              <section className="pf-panel">
                <header className="pf-panel-head"><h2>Ficha do treinador</h2></header>
                <CoachCard stats={p.stats} titles={p.titles?.length ?? p.stats.titles ?? 0} />
              </section>
            )}
            <section className="pf-panel">
              <header className="pf-panel-head"><h2>Insígnias</h2><span className="pf-count">{badges.length}</span></header>
              {tiers.length > 0 && (
                <ul className="fr-tiers" aria-label="Insígnias por nível">
                  {tiers.map((t) => <li key={t.id} className={`t-${t.id}`}><b>{t.n}</b> {t.label}</li>)}
                </ul>
              )}
              <BadgeGrid badges={p.badges} showLocked={false} />
            </section>
            {!p.stats && !p.titles && <p className="pf-hint" style={{ padding: '12px 16px' }}>{p.nickname} preferiu manter a carreira e os títulos privados.</p>}
            {onRemove && p.friendship_id && (
              <button type="button" className="fr-remove" onClick={() => onRemove(p.friendship_id)}><UserMinus size={15} aria-hidden="true" /> Desfazer amizade</button>
            )}
          </>
        )}
      </div>
    </div>
  )
}
