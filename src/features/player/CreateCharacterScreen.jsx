import { useEffect, useMemo, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import {
  UsernameIcon,
  AgeIcon,
  NationalityIcon,
  CheckIcon,
  AlertIcon,
  MinusIcon,
  PlusIcon,
  PlayIcon,
  ShieldIcon,
  StarIcon,
} from '../../components/ui/icons'
import CharacterCard from './components/CharacterCard'
import { CountryFlag } from './components/flags'
import { PROFILE_PHOTOS, getProfilePhotoById } from './data/profilePhotos'
import { COUNTRIES } from './data/countries'
import {
  MIN_AGE,
  MAX_AGE,
  STARTING_LEVEL,
  PLACEHOLDER_XP_TO_NEXT_LEVEL,
} from './data/gameConstants'
import { createPlayer, isNicknameTaken } from './playerService'
import './create-character.css'

export default function CreateCharacterScreen({ userId, onCreated }) {
  const [photoId, setPhotoId] = useState(PROFILE_PHOTOS[0].id)
  const [username, setUsername] = useState('')
  const [age, setAge] = useState('')
  const [country, setCountry] = useState(COUNTRIES[0].id)
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState('')
  const [created, setCreated] = useState(null)

  // 'idle' | 'checking' | 'available' | 'taken'
  const [nicknameStatus, setNicknameStatus] = useState('idle')
  const checkSeq = useRef(0)

  const usernameFormatError = useMemo(() => {
    if (!username) return ''
    if (username.length < 3) return 'Mínimo de 3 caracteres.'
    if (!/^[a-zA-Z0-9_]+$/.test(username)) return 'Use apenas letras, números e "_".'
    return ''
  }, [username])

  // Só consulta o Supabase quando o formato já está certo, com debounce
  // pra não disparar uma chamada de rede a cada tecla digitada.
  useEffect(() => {
    if (!username || usernameFormatError) {
      setNicknameStatus('idle')
      return
    }
    setNicknameStatus('checking')
    const mySeq = ++checkSeq.current
    const timer = setTimeout(async () => {
      const taken = await isNicknameTaken(username)
      if (checkSeq.current !== mySeq) return // usuário já digitou outra coisa
      setNicknameStatus(taken ? 'taken' : 'available')
    }, 450)
    return () => clearTimeout(timer)
  }, [username, usernameFormatError])

  const usernameError = usernameFormatError || (nicknameStatus === 'taken' ? 'Esse username já está em uso.' : '')
  const usernameValid = username.length >= 3 && !usernameFormatError && nicknameStatus === 'available'

  const ageNumber = Number(age)
  const ageError = useMemo(() => {
    if (age === '') return ''
    if (ageNumber < MIN_AGE) return `É preciso ter pelo menos ${MIN_AGE} anos.`
    if (ageNumber > MAX_AGE) return `A idade máxima é ${MAX_AGE} anos.`
    return ''
  }, [age, ageNumber])
  const ageValid = age !== '' && !ageError

  const canSubmit = usernameValid && ageValid && Boolean(photoId) && Boolean(country) && !submitting

  function handleAgeChange(e) {
    setAge(e.target.value.replace(/\D/g, '').slice(0, 2))
  }

  function stepAge(delta) {
    const base = age === '' ? MIN_AGE - delta : ageNumber
    const next = Math.min(MAX_AGE, Math.max(MIN_AGE, base + delta))
    setAge(String(next))
  }

  async function handleSubmit(e) {
    e.preventDefault()
    if (!canSubmit) return
    setSubmitError('')
    setSubmitting(true)
    try {
      const career = await createPlayer({ userId, nickname: username, photoId, country, age: ageNumber })
      setCreated(career)
      onCreated?.(career)
    } catch (err) {
      setSubmitError(err.message || 'Não foi possível criar o personagem.')
    } finally {
      setSubmitting(false)
    }
  }

  const photo = getProfilePhotoById(created ? created.player.photoId : photoId)

  return (
    <AppShell left={<ShieldIcon />} title={created ? 'Personagem criado' : 'Novo personagem'}>
      <LoadingOverlay show={submitting} label="Criando personagem..." />

      {created ? (
        <div className="cc-body cc-success">
          <CharacterCard
            photo={photo}
            nickname={created.player.nickname}
            countryId={created.player.country}
            age={created.player.age}
            level={created.player.level}
            xp={created.player.xp}
            xpToNext={PLACEHOLDER_XP_TO_NEXT_LEVEL}
          />
          <p className="cc-success-msg">
            <CheckIcon /> Sua carreira começou. Bem-vindo, {created.player.nickname}!
          </p>
        </div>
      ) : (
        <form className="cc-screen" onSubmit={handleSubmit} noValidate>
          <div className="cc-body">
            <CharacterCard
              photo={photo}
              nickname={username}
              countryId={country}
              age={ageValid ? ageNumber : null}
              level={STARTING_LEVEL}
              xp={0}
              xpToNext={PLACEHOLDER_XP_TO_NEXT_LEVEL}
            />

            <section>
              <h2 className="section-bar">Ficha do personagem</h2>
              <div className="sheet">
                {/* Foto de perfil: escolhe só uma, sempre redonda */}
                <div className="sheet-row">
                  <span className="sheet-label" id="photo-label">
                    <StarIcon /> Foto
                  </span>
                  <div className="photo-picker" role="radiogroup" aria-labelledby="photo-label">
                    {PROFILE_PHOTOS.map((p) => (
                      <button
                        type="button"
                        key={p.id}
                        role="radio"
                        aria-checked={photoId === p.id}
                        aria-label={p.label}
                        className={`photo-option ${photoId === p.id ? 'is-selected' : ''}`}
                        onClick={() => setPhotoId(p.id)}
                      >
                        <img src={p.src} alt="" />
                        {photoId === p.id && (
                          <span className="photo-check">
                            <CheckIcon size={11} />
                          </span>
                        )}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="sheet-row">
                  <label className="sheet-label" htmlFor="username">
                    <UsernameIcon /> Username
                  </label>
                  <input
                    id="username"
                    className="input"
                    value={username}
                    onChange={(e) => setUsername(e.target.value.trim())}
                    placeholder="Ex: crack_10"
                    maxLength={16}
                    autoComplete="off"
                    autoCapitalize="none"
                    spellCheck={false}
                  />
                  {usernameError && (
                    <p className="sheet-msg is-error">
                      <AlertIcon /> {usernameError}
                    </p>
                  )}
                  {!usernameError && nicknameStatus === 'checking' && (
                    <p className="sheet-msg is-checking">Verificando disponibilidade...</p>
                  )}
                  {usernameValid && (
                    <p className="sheet-msg is-ok">
                      <CheckIcon /> Disponível — único e usado nos duelos 1x1.
                    </p>
                  )}
                </div>

                <div className="sheet-row">
                  <label className="sheet-label" htmlFor="age">
                    <AgeIcon /> Idade
                  </label>
                  <div className="stepper">
                    <button
                      type="button"
                      className="stepper-btn"
                      onClick={() => stepAge(-1)}
                      aria-label="Diminuir idade"
                    >
                      <MinusIcon />
                    </button>
                    <input
                      id="age"
                      className="input stepper-input"
                      value={age}
                      onChange={handleAgeChange}
                      inputMode="numeric"
                      placeholder={String(MIN_AGE)}
                      autoComplete="off"
                    />
                    <button
                      type="button"
                      className="stepper-btn"
                      onClick={() => stepAge(1)}
                      aria-label="Aumentar idade"
                    >
                      <PlusIcon />
                    </button>
                  </div>
                  {ageError && (
                    <p className="sheet-msg is-error">
                      <AlertIcon /> {ageError}
                    </p>
                  )}
                </div>

                <div className="sheet-row">
                  <span className="sheet-label" id="country-label">
                    <NationalityIcon /> Nacionalidade
                  </span>
                  <div className="country-picker" role="radiogroup" aria-labelledby="country-label">
                    {COUNTRIES.map((c) => (
                      <button
                        type="button"
                        key={c.id}
                        role="radio"
                        aria-checked={country === c.id}
                        className={`country-chip ${country === c.id ? 'is-selected' : ''}`}
                        onClick={() => setCountry(c.id)}
                      >
                        <CountryFlag countryId={c.id} />
                        <span>{c.name}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </section>
          </div>

          <div className="cc-footer">
            {submitError && (
              <p className="sheet-msg is-error cc-footer-error">
                <AlertIcon /> {submitError}
              </p>
            )}
            <button type="submit" className="btn-primary" disabled={!canSubmit}>
              <PlayIcon /> Iniciar carreira
            </button>
          </div>
        </form>
      )}
    </AppShell>
  )
}
