import { useCallback, useEffect, useRef, useState } from 'react'
import { ImagePlus, LogOut, Megaphone, Palette, ShieldCheck, Trophy, Users } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { useAuth } from '../../context/AuthContext'
import { getClubById } from '../club/data/clubs'
import ClubCrest from '../club/components/ClubCrest'
import { fetchCompetitions } from '../seasons/services/managerApi'
import BottomTabBar from '../home/components/BottomTabBar'
import { useProfilePrefs } from './profileStore'
import { fetchMyProfile, migrateLocalPrefs, setAvatar } from './services/profileApi'
import ProfileHero from './components/ProfileHero'
import { avatarSrcOf } from './components/ProfileAvatar'
import AvatarPicker from './components/AvatarPicker'
import { BADGE_ART } from './data/badgeArt'
import BadgeGrid from './components/BadgeGrid'
import CoachCard from './components/CoachCard'
import CustomizeSheet from './components/CustomizeSheet'
import PrivacyPanel from './components/PrivacyPanel'
import MusicPlayer from './components/MusicPlayer'
import Sheet from './components/Sheet'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import './profile.css'
import { useAudio } from '../audio/AudioContext'
import { Notice, Skeleton } from '../../components/ui/feedback'

// Perfil = página de identidade do jogador. Tudo vem do servidor (avatar, insígnias, títulos,
// estatísticas, visual e privacidade); o som continua aqui.
export default function ProfileScreen({ career, onNavigate, onOpenNews, onOpenAdmin }) {
  const { player, userId } = career
  const { signOut } = useAuth()
  const [prefs, updatePrefs] = useProfilePrefs(userId) // cache local: a foto do topo da Home usa isto
  const [profile, setProfile] = useState(null)
  const [comps, setComps] = useState({})
  const [error, setError] = useState('')
  const [sheet, setSheet] = useState(null) // 'avatar' | 'customize' | 'logout'
  const [tab, setTab] = useState('career') // 'career' | 'badges' | 'settings'
  const [leaving, setLeaving] = useState(false)
  const migrated = useRef(false)
  const { playSfx } = useAudio()

  const load = useCallback(async () => {
    try {
      let p = await fetchMyProfile()
      // 1ª visita depois da atualização: traz a foto enviada e o banner que ficavam só no navegador
      if (!p.migrated_local && !migrated.current) {
        migrated.current = true
        const local = prefs.avatarUrl?.startsWith('data:image/jpeg') ? prefs.avatarUrl : null
        await migrateLocalPrefs(local, prefs.bannerId || null).catch(() => {})
        const fresh = await fetchMyProfile()
        p = { ...fresh, new_badges: [...(p.new_badges || []), ...(fresh.new_badges || [])] } // não perde o aviso de insígnia nova
      }
      setProfile(p)
      if (p.new_badges?.length) playSfx('levelup')
      updatePrefs({ avatarUrl: avatarSrcOf(p) })
      setError('')
    } catch (e) {
      setError(e.message)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useEffect(() => {
    load()
    fetchCompetitions()
      .then((list) => setComps(Object.fromEntries((list || []).map((c) => [c.id, c]))))
      .catch(() => {})
  }, [load])

  async function changeAvatar(data) {
    await setAvatar(data)
    await load()
  }

  async function confirmLogout() {
    setLeaving(true)
    await signOut()
  }

  const close = () => setSheet(null)
  const st = profile?.stats
  const titles = profile?.titles || []
  const badges = profile?.badges || []
  const earned = badges.filter((b) => b.earned)
  const recent = earned.slice().sort((a, b) => new Date(b.awarded_at) - new Date(a.awarded_at)).slice(0, 4)
  const TABS = [['career', 'Carreira'], ['badges', `Insígnias ${earned.length}/${badges.length}`], ['settings', 'Ajustes']]

  return (
    <AppShell title="Perfil">
      <div className="pf-shell">
        <div className="pf-scroll">
          {!profile ? (
            error ? <div style={{ padding: 14 }}><Notice kind="error">{error}</Notice></div> : (
              <div style={{ padding: 14, display: 'flex', flexDirection: 'column', gap: 12 }}>
                <Skeleton rows={1} variant="tall" />
                <Skeleton rows={3} variant="line" />
              </div>
            )
          ) : (
            <>
              <ProfileHero profile={profile} />

              <nav className="pf-menu" aria-label="Ações do perfil">
                <button type="button" onClick={() => setSheet('customize')}><Palette size={20} /> Visual</button>
                <button type="button" onClick={() => setSheet('avatar')}><ImagePlus size={20} /> Foto</button>
                <button type="button" onClick={() => onNavigate?.('friends')}><Users size={20} /> Amigos</button>
                {onOpenNews && <button type="button" onClick={onOpenNews}><Megaphone size={20} /> Novidades</button>}
                {onOpenAdmin && <button type="button" onClick={onOpenAdmin}><ShieldCheck size={20} /> Painel</button>}
              </nav>

              <div className="pf-tabs" role="tablist" aria-label="Seções do perfil">
                {TABS.map(([id, label]) => (
                  <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>{label}</button>
                ))}
              </div>

              {profile.new_badges?.length > 0 && (
                <p className="pf-newbadge">{profile.new_badges.map((b) => BADGE_ART[b.id] && <img key={b.id} src={BADGE_ART[b.id]} alt="" width={28} height={28} className="pf-newbadge-art" />)} Nova insígnia: {profile.new_badges.map((b) => b.label).join(', ')}!</p>
              )}

              {tab === 'career' && (
                <>
                  {st && (
                    <section className="pf-panel" aria-labelledby="pf-stats-title">
                      <header className="pf-panel-head"><h2 id="pf-stats-title">Ficha do treinador</h2></header>
                      <CoachCard stats={st} titles={titles.length} />
                    </section>
                  )}

                  <section className="pf-panel" aria-labelledby="pf-titles-title">
                    <header className="pf-panel-head"><h2 id="pf-titles-title">Sala de troféus</h2><span className="pf-count">{titles.length}</span></header>
                    {titles.length === 0 ? (
                      <div className="pf-shelf-empty">
                        <Trophy size={30} aria-hidden="true" />
                        <p><b>A prateleira está vazia</b>Conquiste um campeonato e a taça aparece aqui.</p>
                      </div>
                    ) : (
                      <ul className="pf-titles">
                        {titles.map((t, i) => (
                          <li key={`${t.competition}-${t.year}-${i}`}>
                            <span className="pf-trophy" aria-hidden="true"><Trophy size={18} /></span>
                            <span><strong>{comps[t.competition]?.name || t.competition}</strong><small>{t.year} · {getClubById(t.club_id)?.name || t.club_id}</small></span>
                            <ClubCrest clubId={t.club_id} size={26} />
                          </li>
                        ))}
                      </ul>
                    )}
                  </section>

                  <section className="pf-panel" aria-labelledby="pf-recent-title">
                    <header className="pf-panel-head">
                      <h2 id="pf-recent-title">Últimas insígnias</h2>
                      <button type="button" className="pf-more" onClick={() => setTab('badges')}>Ver todas</button>
                    </header>
                    {recent.length === 0 ? <p className="pf-hint">Nenhuma insígnia conquistada ainda.</p> : (
                      <ul className="pf-recent">
                        {recent.map((b) => (
                          <li key={b.id}>
                            {BADGE_ART[b.id] && <img src={BADGE_ART[b.id]} alt="" width={56} height={56} loading="lazy" />}
                            <span>{b.label}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </section>
                </>
              )}

              {tab === 'badges' && (
                <section className="pf-panel" aria-labelledby="pf-badges-title">
                  <header className="pf-panel-head"><h2 id="pf-badges-title">Insígnias</h2><span className="pf-count">{earned.length}/{badges.length}</span></header>
                  <BadgeGrid badges={badges} />
                </section>
              )}

              {tab === 'settings' && <PrivacyPanel privacy={profile.privacy} onChanged={load} />}
            </>
          )}

          {(tab === 'settings' || !profile) && (
            <>
              <MusicPlayer />

              <section className="pf-panel" aria-labelledby="pf-account-title">
                <header className="pf-panel-head">
                  <h2 id="pf-account-title">Conta</h2>
                </header>
                <p className="pf-hint">O progresso fica salvo na sua conta e acompanha você em qualquer aparelho.</p>
                <button type="button" className="pf-btn danger block" onClick={() => setSheet('logout')}>
                  <LogOut size={16} />
                  Sair da conta
                </button>
              </section>
            </>
          )}
        </div>

        <BottomTabBar active="profile" onSelect={onNavigate} />

        {sheet === 'avatar' && profile && (
          <AvatarPicker currentSrc={avatarSrcOf(profile)} originalSrc={getProfilePhotoById(player.photoId)?.src ?? null} onChange={changeAvatar} onClose={close} owned={profile.avatars || []} />
        )}
        {sheet === 'customize' && profile && (
          <CustomizeSheet profile={profile} onClose={close} onChanged={load} onOpenStore={() => onNavigate?.('store', { tab: 'visual' })} />
        )}
        {sheet === 'logout' && (
          <Sheet title="Sair da conta?" onClose={close}>
            <p className="pf-hint">Seu progresso fica salvo. Você poderá voltar a qualquer momento entrando com a mesma conta.</p>
            <div className="pf-actions two">
              <button type="button" className="pf-btn" onClick={close} disabled={leaving}>Cancelar</button>
              <button type="button" className="pf-btn danger solid" onClick={confirmLogout} disabled={leaving}>{leaving ? 'Saindo...' : 'Sair'}</button>
            </div>
          </Sheet>
        )}
      </div>
    </AppShell>
  )
}
