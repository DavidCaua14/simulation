import { useCallback, useEffect, useRef, useState } from 'react'
import { Palette, Users } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import ThemeToggle from '../../components/ThemeToggle'
import { useTheme } from '../../context/ThemeContext'
import { useAuth } from '../../context/AuthContext'
import { getClubById } from '../club/data/clubs'
import ClubCrest from '../club/components/ClubCrest'
import { tierOf, TIER_ORDER } from '../cards/data/tiers'
import { fetchCompetitions } from '../seasons/services/managerApi'
import BottomTabBar from '../home/components/BottomTabBar'
import { useProfilePrefs } from './profileStore'
import { fetchMyProfile, migrateLocalPrefs, setAvatar } from './services/profileApi'
import ProfileHero from './components/ProfileHero'
import { avatarSrcOf } from './components/ProfileAvatar'
import AvatarPicker from './components/AvatarPicker'
import BadgeGrid from './components/BadgeGrid'
import FeaturedCardPanel from './components/FeaturedCardPanel'
import CustomizeSheet from './components/CustomizeSheet'
import PrivacyPanel from './components/PrivacyPanel'
import MusicPlayer from './components/MusicPlayer'
import Sheet from './components/Sheet'
import { LogOutIcon, PencilIcon } from './components/ProfileIcons'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import './profile.css'

// Perfil = página de identidade do jogador. Tudo vem do servidor (avatar, carta em destaque, insígnias, títulos,
// estatísticas, visual e privacidade); o som e o tema continuam aqui.
export default function ProfileScreen({ career, onNavigate }) {
  const { player, userId } = career
  const { signOut } = useAuth()
  const { theme, toggleTheme } = useTheme()
  const [prefs, updatePrefs] = useProfilePrefs(userId) // cache local: a foto do topo da Home usa isto
  const [profile, setProfile] = useState(null)
  const [comps, setComps] = useState({})
  const [error, setError] = useState('')
  const [sheet, setSheet] = useState(null) // 'avatar' | 'customize' | 'logout'
  const [leaving, setLeaving] = useState(false)
  const migrated = useRef(false)

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
  const col = profile?.collection
  const titles = profile?.titles || []

  return (
    <AppShell title="Perfil">
      <div className="pf-shell">
        <div className="pf-scroll">
          {!profile ? (
            error ? <p className="pf-error">{error}</p> : <p className="pf-hint" style={{ textAlign: 'center', padding: 40 }}>Carregando perfil…</p>
          ) : (
            <>
              <ProfileHero
                profile={profile}
                actions={
                  <>
                    <button type="button" className="pf-edit-pill" onClick={() => setSheet('customize')}><Palette size={14} /> Personalizar</button>
                    <button type="button" className="pf-edit-pill" onClick={() => setSheet('avatar')}><PencilIcon size={14} /> Foto</button>
                    <button type="button" className="pf-edit-pill" onClick={() => onNavigate?.('friends')} aria-label="Amigos"><Users size={14} /></button>
                  </>
                }
              />

              {profile.new_badges?.length > 0 && (
                <p className="pf-newbadge">🏅 Nova insígnia: {profile.new_badges.map((b) => b.label).join(', ')}!</p>
              )}

              <FeaturedCardPanel card={profile.featured_card} editable onChanged={load} />

              <section className="pf-panel" aria-labelledby="pf-badges-title">
                <header className="pf-panel-head"><h2 id="pf-badges-title">Insígnias</h2></header>
                <BadgeGrid badges={profile.badges} />
              </section>

              {st && (
                <section className="pf-panel" aria-labelledby="pf-stats-title">
                  <header className="pf-panel-head"><h2 id="pf-stats-title">Carreira de treinador</h2></header>
                  <dl className="pf-stats six">
                    <div><dt>Jogos</dt><dd>{st.matches}</dd></div>
                    <div><dt>Vitórias</dt><dd>{st.wins}</dd></div>
                    <div><dt>Empates</dt><dd>{st.draws}</dd></div>
                    <div><dt>Derrotas</dt><dd>{st.losses}</dd></div>
                    <div><dt>Gols</dt><dd>{st.gf}–{st.ga}</dd></div>
                    <div><dt>Temporadas</dt><dd>{st.seasons}</dd></div>
                  </dl>
                </section>
              )}

              <section className="pf-panel" aria-labelledby="pf-titles-title">
                <header className="pf-panel-head"><h2 id="pf-titles-title">Títulos</h2><span className="pf-count">{titles.length}</span></header>
                {titles.length === 0 ? <p className="pf-hint">Nenhum título ainda. A primeira taça vira uma insígnia!</p> : (
                  <ul className="pf-titles">
                    {titles.map((t, i) => (
                      <li key={`${t.competition}-${t.year}-${i}`}>
                        <span className="pf-trophy" aria-hidden="true">🏆</span>
                        <span><strong>{comps[t.competition]?.name || t.competition}</strong><small>{t.year} · {getClubById(t.club_id)?.name || t.club_id}</small></span>
                        <ClubCrest clubId={t.club_id} size={22} />
                      </li>
                    ))}
                  </ul>
                )}
              </section>

              {col && (
                <section className="pf-panel" aria-labelledby="pf-col-title">
                  <header className="pf-panel-head">
                    <h2 id="pf-col-title">Coleção</h2>
                    <button type="button" className="pf-link" onClick={() => onNavigate?.('cards', { tab: 'collection' })}>Abrir</button>
                  </header>
                  <p className="pf-hint">{col.owned} de {col.total} cartas</p>
                  <div className="pf-col-bars">
                    {TIER_ORDER.slice().reverse().map((t) => (
                      <div key={t} style={{ '--tier': tierOf(t).color }}>
                        <span>{tierOf(t).label}</span>
                        <b>{col.by_tier?.[t] || 0}</b>
                      </div>
                    ))}
                  </div>
                </section>
              )}

              <PrivacyPanel privacy={profile.privacy} onChanged={load} />
            </>
          )}

          <MusicPlayer />

          <section className="pf-panel" aria-labelledby="pf-account-title">
            <header className="pf-panel-head">
              <h2 id="pf-account-title">Conta</h2>
            </header>
            <div className="pf-row">
              <span>Tema {theme === 'dark' ? 'escuro' : 'claro'}</span>
              <ThemeToggle isDark={theme === 'dark'} onToggle={toggleTheme} />
            </div>
            <button type="button" className="pf-btn danger block" onClick={() => setSheet('logout')}>
              <LogOutIcon size={16} />
              Sair da conta
            </button>
          </section>
        </div>

        <BottomTabBar active="profile" onSelect={onNavigate} />

        {sheet === 'avatar' && profile && (
          <AvatarPicker currentSrc={avatarSrcOf(profile)} originalSrc={getProfilePhotoById(player.photoId)?.src ?? null} onChange={changeAvatar} onClose={close} />
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
