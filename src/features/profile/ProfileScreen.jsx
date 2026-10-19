import { useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import ThemeToggle from '../../components/ThemeToggle'
import { useTheme } from '../../context/ThemeContext'
import { useAuth } from '../../context/AuthContext'
import { getClubById } from '../club/data/clubs'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import { PLACEHOLDER_XP_TO_NEXT_LEVEL } from '../player/data/gameConstants'
import BottomTabBar from '../home/components/BottomTabBar'
import { getBanner, bannerStyle } from './data/banners'
import { useProfilePrefs } from './profileStore'
import AvatarPicker from './components/AvatarPicker'
import BannerPicker from './components/BannerPicker'
import CardShowcase from './components/CardShowcase'
import MusicPlayer from './components/MusicPlayer'
import Sheet from './components/Sheet'
import { LogOutIcon, PencilIcon, UserIcon } from './components/ProfileIcons'
import './profile.css'

export default function ProfileScreen({ career, onNavigate }) {
  const { player, userId } = career
  const { signOut } = useAuth()
  const { theme, toggleTheme } = useTheme()
  const club = getClubById(player.clubId)
  const originalPhoto = getProfilePhotoById(player.photoId)?.src ?? null

  const [prefs, update] = useProfilePrefs(userId)
  const [sheet, setSheet] = useState(null) // 'banner' | 'avatar' | 'logout' | null
  const [leaving, setLeaving] = useState(false)

  const banner = getBanner(prefs.bannerId)
  const avatarSrc = prefs.avatarUrl || originalPhoto
  const xp = player.xp ?? 0
  const pct = Math.max(0, Math.min(100, (xp / PLACEHOLDER_XP_TO_NEXT_LEVEL) * 100))
  const close = () => setSheet(null)

  async function confirmLogout() {
    setLeaving(true)
    await signOut() // o Gate volta para o login sozinho
  }

  const stats = [
    { label: 'Nível', value: player.level },
    { label: 'XP', value: xp.toLocaleString('pt-BR') },
    { label: 'Camisa', value: player.jerseyNumber != null ? `#${player.jerseyNumber}` : '—' },
    { label: 'Posição', value: player.position || '—' },
  ]

  return (
    <AppShell title="Perfil">
      <div className="pf-shell">
        <div className="pf-scroll">
          {/* Banner + foto */}
          <div className="pf-hero">
            <div className="pf-banner" style={bannerStyle(banner)}>
              <button type="button" className="pf-edit-pill" onClick={() => setSheet('banner')}>
                <PencilIcon size={14} />
                Editar banner
              </button>
            </div>

            <div className="pf-avatar-wrap">
              <span className="pf-avatar" style={{ '--xp': pct }}>
                <span className="pf-avatar-img">
                  {avatarSrc ? <img src={avatarSrc} alt="" /> : <UserIcon size={34} />}
                </span>
              </span>
              <button type="button" className="pf-avatar-edit" onClick={() => setSheet('avatar')} aria-label="Editar foto de perfil">
                <PencilIcon size={13} />
              </button>
            </div>
          </div>

          {/* Identidade */}
          <div className="pf-identity">
            <h1>{player.nickname}</h1>
            <p>{[club?.name, player.position].filter(Boolean).join(' · ') || 'Jogador'}</p>
            <div className="pf-xpbar" aria-hidden="true">
              <i style={{ width: `${pct}%` }} />
            </div>
          </div>

          <dl className="pf-stats">
            {stats.map((s) => (
              <div key={s.label}>
                <dt>{s.label}</dt>
                <dd>{s.value}</dd>
              </div>
            ))}
          </dl>

          <CardShowcase isPublic={prefs.showcasePublic} onTogglePublic={(v) => update({ showcasePublic: v })} />

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

        {sheet === 'banner' && <BannerPicker selectedId={banner.id} onSelect={(id) => update({ bannerId: id })} onClose={close} />}
        {sheet === 'avatar' && (
          <AvatarPicker currentSrc={avatarSrc} originalSrc={originalPhoto} onChange={(src) => update({ avatarUrl: src })} onClose={close} />
        )}
        {sheet === 'logout' && (
          <Sheet title="Sair da conta?" onClose={close}>
            <p className="pf-hint">Seu progresso fica salvo. Você poderá voltar a qualquer momento entrando com a mesma conta.</p>
            <div className="pf-actions two">
              <button type="button" className="pf-btn" onClick={close} disabled={leaving}>
                Cancelar
              </button>
              <button type="button" className="pf-btn danger solid" onClick={confirmLogout} disabled={leaving}>
                {leaving ? 'Saindo...' : 'Sair'}
              </button>
            </div>
          </Sheet>
        )}
      </div>
    </AppShell>
  )
}
