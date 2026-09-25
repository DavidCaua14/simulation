import { useRef, useState } from 'react'
import { AVATAR_PRESETS } from '../data/avatarPresets'
import { resizeImageFile } from '../utils/resizeImage'
import { UserIcon, CameraIcon, AlertIcon } from '../../../components/ui/icons'

export default function AvatarStep({ value, onChange, onNext }) {
  const fileInputRef = useRef(null)
  const [photoError, setPhotoError] = useState('')

  const hasSelection = Boolean(value.avatarId || value.avatarPhoto)

  async function handlePhotoChange(e) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    if (!file.type.startsWith('image/')) {
      setPhotoError('Envie um arquivo de imagem.')
      return
    }
    try {
      const dataUrl = await resizeImageFile(file)
      setPhotoError('')
      onChange({ avatarPhoto: dataUrl, avatarId: null })
    } catch {
      setPhotoError('Não foi possível processar essa imagem.')
    }
  }

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Escolha seu avatar</h1>
        <p>Envie uma foto ou escolha um avatar padrão para representar seu jogador.</p>
      </div>

      <div className="step-body">
        <div className="avatar-preview-row">
          <button type="button" className="avatar-upload-tile" onClick={() => fileInputRef.current?.click()}>
            {value.avatarPhoto ? (
              <img src={value.avatarPhoto} alt="Sua foto" className="avatar-photo-preview" />
            ) : (
              <>
                <CameraIcon />
                <span>Enviar foto</span>
              </>
            )}
          </button>
          <input ref={fileInputRef} type="file" accept="image/*" hidden onChange={handlePhotoChange} />
        </div>
        {photoError && (
          <p className="field-error">
            <AlertIcon /> {photoError}
          </p>
        )}

        <span className="field-label">Ou escolha um avatar padrão</span>
        <div className="avatar-grid">
          {AVATAR_PRESETS.map((preset) => (
            <button
              type="button"
              key={preset.id}
              className={`avatar-option ${value.avatarId === preset.id ? 'is-selected' : ''}`}
              style={{ background: preset.color }}
              onClick={() => onChange({ avatarId: preset.id, avatarPhoto: null })}
              aria-label={`Selecionar avatar ${preset.id}`}
            >
              <UserIcon width="20" height="20" stroke="#fff" />
            </button>
          ))}
        </div>
      </div>

      <div className="step-footer">
        <button type="button" className="btn-primary" disabled={!hasSelection} onClick={onNext}>
          Próximo
        </button>
      </div>
    </div>
  )
}
