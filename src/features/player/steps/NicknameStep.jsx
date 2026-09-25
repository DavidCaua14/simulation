import { useMemo } from 'react'
import { UserIcon, AlertIcon, CheckIcon } from '../../../components/ui/icons'
import { isNicknameTaken } from '../playerService'

export default function NicknameStep({ value, onChange, onNext, onBack }) {
  const nickname = value.nickname

  const nicknameError = useMemo(() => {
    if (!nickname) return ''
    if (nickname.length < 3) return 'Mínimo de 3 caracteres.'
    if (nickname.length > 16) return 'Máximo de 16 caracteres.'
    if (!/^[a-zA-Z0-9_]+$/.test(nickname)) return 'Use apenas letras, números e "_".'
    if (isNicknameTaken(nickname)) return 'Esse nickname já está em uso.'
    return ''
  }, [nickname])

  const isValid = nickname.length >= 3 && !nicknameError

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Nickname</h1>
        <p>Esse será o nome público do seu jogador — único no jogo, usado nos duelos 1x1.</p>
      </div>

      <div className="step-body">
        <label className="field-label" htmlFor="nickname">
          <UserIcon /> Nickname
        </label>
        <input
          id="nickname"
          className="input"
          value={nickname}
          onChange={(e) => onChange({ nickname: e.target.value })}
          placeholder="Ex: crack_10"
          maxLength={16}
          autoComplete="off"
          autoFocus
        />
        {nicknameError && (
          <p className="field-error">
            <AlertIcon /> {nicknameError}
          </p>
        )}
        {isValid && (
          <p className="field-hint field-hint-ok">
            <CheckIcon /> Nickname disponível.
          </p>
        )}
      </div>

      <div className="step-footer">
        <button type="button" className="btn-secondary" onClick={onBack}>
          Voltar
        </button>
        <button type="button" className="btn-primary" disabled={!isValid} onClick={onNext}>
          Próximo
        </button>
      </div>
    </div>
  )
}
