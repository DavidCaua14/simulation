import { useMemo, useState } from 'react'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import { UserIcon, ShirtIcon, HashIcon, CheckIcon, AlertIcon } from '../../components/ui/icons'
import { AVATARS } from './avatars'
import { POSITIONS } from './positions'
import { createPlayer, isNicknameTaken } from './playerService'
import './CreatePlayerScreen.css'

const FIXED_AGE = 16

export default function CreatePlayerScreen({ onCreated }) {
  const [avatarId, setAvatarId] = useState(AVATARS[0].id)
  const [nickname, setNickname] = useState('')
  const [position, setPosition] = useState(POSITIONS[5].id)
  const [jerseyNumber, setJerseyNumber] = useState('10')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const nicknameError = useMemo(() => {
    if (!nickname) return ''
    if (nickname.length < 3) return 'Mínimo de 3 caracteres.'
    if (nickname.length > 16) return 'Máximo de 16 caracteres.'
    if (!/^[a-zA-Z0-9_]+$/.test(nickname)) return 'Use apenas letras, números e "_".'
    if (isNicknameTaken(nickname)) return 'Esse nickname já está em uso.'
    return ''
  }, [nickname])

  const jerseyError = useMemo(() => {
    const n = Number(jerseyNumber)
    if (!jerseyNumber) return 'Informe um número.'
    if (!Number.isInteger(n) || n < 1 || n > 99) return 'Escolha um número entre 1 e 99.'
    return ''
  }, [jerseyNumber])

  const canSubmit = nickname.length >= 3 && !nicknameError && !jerseyError && !loading

  async function handleSubmit(e) {
    e.preventDefault()
    if (!canSubmit) return
    setError('')
    setLoading(true)
    try {
      const career = await createPlayer({ nickname, avatarId, position, jerseyNumber })
      onCreated?.(career)
    } catch (err) {
      setError(err.message || 'Não foi possível criar o técnico.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="create-player">
      <LoadingOverlay show={loading} label="Criando técnico..." />

      <div className="create-player-intro">
        <h1 className="heading">Novo Técnico</h1>
        <p>
          Configure sua primeira temporada. Você começa aos {FIXED_AGE} anos, com
          atributos baixos, e evolui treinando e jogando.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="create-player-form">
        <section className="card form-section">
          <span className="field-label">Avatar</span>
          <div className="avatar-grid">
            {AVATARS.map((avatar) => (
              <button
                type="button"
                key={avatar.id}
                className={`avatar-option ${avatarId === avatar.id ? 'is-selected' : ''}`}
                onClick={() => setAvatarId(avatar.id)}
                aria-label={`Selecionar avatar ${avatar.id}`}
              >
                {avatar.render()}
                {avatarId === avatar.id && (
                  <span className="avatar-check">
                    <CheckIcon />
                  </span>
                )}
              </button>
            ))}
          </div>
        </section>

        <section className="card form-section">
          <label className="field-label" htmlFor="nickname">
            <UserIcon /> Nickname
          </label>
          <input
            id="nickname"
            className="input"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            placeholder="Ex: crack_10"
            maxLength={16}
            autoComplete="off"
          />
          {nicknameError && (
            <p className="field-error">
              <AlertIcon /> {nicknameError}
            </p>
          )}
          <p className="field-hint">Único no jogo — identifica seu técnico.</p>
        </section>

        <section className="card form-section">
          <span className="field-label">Posição</span>
          <div className="position-grid">
            {POSITIONS.map((pos) => (
              <button
                type="button"
                key={pos.id}
                className={`position-chip ${position === pos.id ? 'is-selected' : ''}`}
                onClick={() => setPosition(pos.id)}
              >
                {pos.label}
              </button>
            ))}
          </div>
        </section>

        <section className="card form-section form-row">
          <div>
            <label className="field-label" htmlFor="jersey">
              <ShirtIcon /> Número
            </label>
            <div className="jersey-input-wrap">
              <HashIcon />
              <input
                id="jersey"
                className="input jersey-input"
                type="number"
                min={1}
                max={99}
                value={jerseyNumber}
                onChange={(e) => setJerseyNumber(e.target.value)}
              />
            </div>
            {jerseyError && (
              <p className="field-error">
                <AlertIcon /> {jerseyError}
              </p>
            )}
          </div>
          <div>
            <span className="field-label">Idade</span>
            <div className="age-badge">{FIXED_AGE} anos</div>
            <p className="field-hint">Envelhece a cada temporada.</p>
          </div>
        </section>

        {error && (
          <p className="field-error form-error">
            <AlertIcon /> {error}
          </p>
        )}

        <button type="submit" className="btn-primary" disabled={!canSubmit}>
          {loading ? 'Criando...' : 'Começar carreira'}
        </button>
      </form>
    </div>
  )
}
