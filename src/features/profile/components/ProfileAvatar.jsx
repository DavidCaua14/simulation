import { getProfilePhotoById } from '../../player/data/profilePhotos'
import { UserIcon } from './ProfileIcons'
import { AVATAR_ART } from '../data/avatars'

// Resolve a foto do perfil: enviada (data URL), foto pronta do jogo ('preset:<id>'), avatar ganho ('avatar:<id>') ou a da criação (photo_id)
export function avatarSrcOf(profile) {
  const a = profile?.avatar
  if (a?.startsWith('data:image/')) return a
  if (a?.startsWith('preset:')) return getProfilePhotoById(a.slice(7))?.src ?? null
  if (a?.startsWith('avatar:')) return AVATAR_ART[a.slice(7)] ?? null
  return getProfilePhotoById(profile?.photo_id)?.src ?? null
}

// Avatar com a MOLDURA e o EFEITO equipados (cosméticos: só aparência)
export default function ProfileAvatar({ profile, frame, effect, size = 108, xpPct }) {
  const src = avatarSrcOf(profile)
  const ring = frame?.style?.ring
  const fx = effect?.style?.type
  const style = {
    '--av-size': `${size}px`,
    '--av-ring': ring || 'conic-gradient(var(--pf-accent, var(--primary)) calc(var(--xp, 0) * 1%), rgba(255,255,255,.14) 0)',
    '--av-glow': frame?.style?.glow || 'transparent',
    '--fx-color': effect?.style?.color || '#fde68a',
    '--xp': xpPct ?? 0,
  }
  return (
    <span className={`pa ${ring ? 'has-frame' : ''} ${frame?.style?.spin ? 'is-spin' : ''} ${fx ? `fx-${fx}` : ''}`} style={style}>
      <span className="pa-ring" aria-hidden="true" />
      <span className="pa-img">
        {src ? <img src={src} alt="" /> : profile?.nickname ? (
          <b className="pa-initial" style={{ fontSize: Math.round(size * 0.42) }}>{profile.nickname.charAt(0).toUpperCase()}</b>
        ) : <UserIcon size={Math.round(size / 3)} />}
      </span>
      {fx === 'sparks' && (
        <span className="pa-sparks" aria-hidden="true">
          <i /><i /><i /><i /><i /><i />
        </span>
      )}
    </span>
  )
}
