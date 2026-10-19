import { useRef, useState } from 'react'
import * as photoModule from '../../player/data/profilePhotos'
import { fileToAvatar } from '../profileStore'
import { CheckIcon, UploadIcon, UserIcon } from './ProfileIcons'
import Sheet from './Sheet'

// Lê a lista de fotos prontas do arquivo existente, seja qual for o nome da exportação.
const PRESET_PHOTOS = Object.values(photoModule).find((v) => Array.isArray(v)) ?? []

export default function AvatarPicker({ currentSrc, originalSrc, onChange, onClose }) {
  const inputRef = useRef(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function handleFile(e) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setError('')
    setBusy(true)
    try {
      onChange(await fileToAvatar(file))
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Sheet title="Foto de perfil" onClose={onClose}>
      <div className="pf-avatar-preview">
        <span className="pf-avatar-lg">
          {currentSrc ? <img src={currentSrc} alt="" /> : <UserIcon size={34} />}
        </span>
      </div>

      {PRESET_PHOTOS.length > 0 && (
        <>
          <h4 className="pf-sub">Fotos do jogo</h4>
          <div className="pf-photo-grid">
            {PRESET_PHOTOS.map((p, i) => {
              const on = p.src === currentSrc
              return (
                <button
                  key={p.id ?? i}
                  type="button"
                  className={`pf-photo ${on ? 'is-on' : ''}`}
                  onClick={() => onChange(p.src)}
                  aria-label={p.name ?? `Foto ${i + 1}`}
                  aria-pressed={on}
                >
                  <img src={p.src} alt="" />
                  {on && (
                    <span className="pf-swatch-check">
                      <CheckIcon size={12} />
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        </>
      )}

      <input ref={inputRef} type="file" accept="image/*" hidden onChange={handleFile} />
      <div className="pf-actions">
        <button type="button" className="pf-btn" onClick={() => inputRef.current?.click()} disabled={busy}>
          <UploadIcon size={16} />
          {busy ? 'Enviando...' : 'Enviar da galeria'}
        </button>
        {originalSrc && currentSrc !== originalSrc && (
          <button type="button" className="pf-btn ghost" onClick={() => onChange(null)}>
            Voltar à foto original
          </button>
        )}
      </div>
      {error && (
        <p className="pf-error" role="alert">
          {error}
        </p>
      )}

      <button type="button" className="pf-btn primary block" onClick={onClose}>
        Concluir
      </button>
    </Sheet>
  )
}
