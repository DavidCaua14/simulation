import { useMemo } from 'react'
import { UserIcon, AlertIcon, CheckIcon } from '../../../components/ui/icons'
import { isNicknameTaken } from '../playerService'
import { COUNTRIES } from '../data/countries'
import { CountryFlag } from '../components/flags'
import PlayerCard from '../components/PlayerCard'

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

  const isValid = nickname.length >= 3 && !nicknameError && Boolean(value.country)

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Nickname e país</h1>
        <p>O nickname é único no jogo e usado nos duelos 1x1. O país define os times disponíveis na carreira.</p>
      </div>

      <div className="step-body">
        <PlayerCard appearance={value.appearance} nickname={nickname} countryId={value.country} />

        <div>
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
          {isValid && !nicknameError && (
            <p className="field-hint field-hint-ok">
              <CheckIcon /> Nickname disponível.
            </p>
          )}
        </div>

        <div>
          <span className="field-label">País</span>
          <div className="country-grid">
            {COUNTRIES.map((country) => (
              <button
                type="button"
                key={country.id}
                className={`country-chip ${value.country === country.id ? 'is-selected' : ''}`}
                onClick={() => onChange({ country: country.id })}
              >
                <CountryFlag countryId={country.id} />
                <span>{country.name}</span>
              </button>
            ))}
          </div>
          <p className="field-hint">Define as opções iniciais de times da carreira.</p>
        </div>
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
