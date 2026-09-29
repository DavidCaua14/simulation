import { AVATAR_PRESETS } from '../data/avatarPresets'
import AvatarBust from '../components/AvatarBust'

export default function AvatarStep({ value, onChange, onNext }) {
  const hasSelection = Boolean(value.avatarId)

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Escolha seu avatar</h1>
        <p>Esse é o rosto do seu jogador dentro do jogo. Dá para trocar depois na loja.</p>
      </div>

      <div className="step-body">
        <div className="avatar-grid">
          {AVATAR_PRESETS.map((preset) => (
            <button
              type="button"
              key={preset.id}
              className={`avatar-option ${value.avatarId === preset.id ? 'is-selected' : ''}`}
              onClick={() => onChange({ avatarId: preset.id })}
              aria-label={`Selecionar avatar ${preset.id}`}
            >
              <AvatarBust {...preset} />
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
