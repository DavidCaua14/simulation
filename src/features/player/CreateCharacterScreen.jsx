import { useEffect, useMemo, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import SignOutButton from '../../components/ui/SignOutButton'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import { AgeIcon, NationalityIcon, CheckIcon, AlertIcon, MinusIcon, PlusIcon, PlayIcon } from '../../components/ui/icons'
import { CountryFlag } from './components/flags'
import { PROFILE_PHOTOS, getProfilePhotoById } from './data/profilePhotos'
import { COUNTRIES, getCountryById } from './data/countries'
import { MIN_AGE, MAX_AGE, STARTING_LEVEL, XP_PER_LEVEL } from './data/gameConstants'
import { createPlayer, isNicknameTaken } from './playerService'
import stageBg from '../home/assets/temporadas.webp'
import './create-character.css'

// Criação do atleta: o personagem fica no centro (palco iluminado), a ficha logo abaixo
// e o botão de iniciar a carreira fixo no rodapé. A lógica (validação, checagem do username
// no banco, criação da carreira) é a mesma de antes.
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
  const steps = [Boolean(photoId), usernameValid, ageValid, Boolean(country)]
  const done = steps.filter(Boolean).length
  const missing = !usernameValid ? 'Escolha um username disponível' : !ageValid ? 'Informe sua idade' : ''

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
  const shownName = created ? created.player.nickname : username
  const countryObj = getCountryById(created ? created.player.country : country)
  const shownAge = created ? created.player.age : ageValid ? ageNumber : null
  const subtitle = [countryObj?.name, shownAge ? `${shownAge} anos` : null, 'Estreante'].filter(Boolean).join(' · ')

  const stage = (
    <section className="ca-stage" aria-label="Seu atleta">
      <img className="ca-stage-bg" src={stageBg} alt="" />
      <span className="ca-beam left" aria-hidden="true" />
      <span className="ca-beam right" aria-hidden="true" />

      <span className="ca-kicker">{created ? 'Contrato de estreia' : 'Sua carreira começa aqui'}</span>

      <div className="ca-avatar">
        <span className="ca-avatar-glow" aria-hidden="true" />
        <div className="gx-frame ca-avatar-frame">
          {photo ? <img key={photo.id} src={photo.src} alt={`Visual: ${photo.label}`} /> : <span className="gx-frame-inner" />}
        </div>
        <span className="ca-level">
          <small>NV</small>
          {created ? created.player.level : STARTING_LEVEL}
        </span>
      </div>

      <h1 className={`ca-name ${shownName ? '' : 'is-placeholder'}`}>
        <span>{shownName || 'Seu nome'}</span>
        {countryObj && <CountryFlag countryId={countryObj.id} />}
      </h1>
      <p className="ca-sub">{subtitle}</p>

      <div className="ca-xp" aria-label={`Experiência: 0 de ${XP_PER_LEVEL}`}>
        <span>XP</span>
        <div className="gx-xp">
          <i style={{ width: '0%' }} />
        </div>
        <span>0 / {XP_PER_LEVEL.toLocaleString('pt-BR')}</span>
      </div>

      {!created && (
        <div className="ca-looks">
          <span className="ca-looks-label" id="photo-label">
            Visual
          </span>
          <div className="ca-looks-list" role="radiogroup" aria-labelledby="photo-label">
            {PROFILE_PHOTOS.map((p) => (
              <button
                type="button"
                key={p.id}
                role="radio"
                aria-checked={photoId === p.id}
                aria-label={p.label}
                className={`ca-look ${photoId === p.id ? 'is-selected' : ''}`}
                onClick={() => setPhotoId(p.id)}
              >
                <img src={p.src} alt="" />
                {photoId === p.id && (
                  <span className="ca-look-check">
                    <CheckIcon size={10} />
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  )

  return (
    <AppShell left={<SignOutButton />} title={created ? 'Atleta criado' : 'Criar atleta'}>
      <LoadingOverlay show={submitting} label="Criando seu atleta..." />

      {created ? (
        <div className="ca-screen">
          <div className="ca-scroll">
            {stage}
            <p className="ca-success">
              <CheckIcon /> Sua carreira começou. Bem-vindo, {created.player.nickname}!
            </p>
          </div>
        </div>
      ) : (
        <form className="ca-screen" onSubmit={handleSubmit} noValidate>
          <div className="ca-scroll">
            {stage}

            <section className="gx-panel ca-sheet">
              <h2 className="gx-title">
                Ficha do atleta <small>{done}/4 prontos</small>
              </h2>

              {/* Username */}
              <div className="ca-field">
                <label className="ca-label" htmlFor="username">
                  Username <em>usado nos duelos 1x1</em>
                </label>
                <div className={`ca-input ${usernameError ? 'is-error' : usernameValid ? 'is-ok' : ''}`}>
                  <span className="ca-input-at" aria-hidden="true">
                    @
                  </span>
                  <input
                    id="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value.trim())}
                    placeholder="crack_10"
                    maxLength={16}
                    autoComplete="off"
                    autoCapitalize="none"
                    spellCheck={false}
                    aria-invalid={Boolean(usernameError)}
                    aria-describedby="username-msg"
                  />
                  <span className="ca-input-state" aria-hidden="true">
                    {nicknameStatus === 'checking' && !usernameError && <span className="ca-spin" />}
                    {usernameValid && <CheckIcon size={14} />}
                    {usernameError && <AlertIcon size={14} />}
                  </span>
                </div>
                <p id="username-msg" className={`ca-msg ${usernameError ? 'is-error' : usernameValid ? 'is-ok' : ''}`} aria-live="polite">
                  {usernameError ||
                    (nicknameStatus === 'checking' ? 'Verificando disponibilidade…' : usernameValid ? 'Disponível!' : '3 a 16 caracteres: letras, números e _')}
                </p>
              </div>

              <div className="ca-row">
                {/* Idade */}
                <div className="ca-field">
                  <label className="ca-label" htmlFor="age">
                    <AgeIcon size={13} /> Idade
                  </label>
                  <div className={`ca-stepper ${ageError ? 'is-error' : ''}`}>
                    <button type="button" onClick={() => stepAge(-1)} aria-label="Diminuir idade">
                      <MinusIcon size={15} />
                    </button>
                    <input
                      id="age"
                      value={age}
                      onChange={handleAgeChange}
                      inputMode="numeric"
                      placeholder={String(MIN_AGE)}
                      autoComplete="off"
                      aria-invalid={Boolean(ageError)}
                    />
                    <button type="button" onClick={() => stepAge(1)} aria-label="Aumentar idade">
                      <PlusIcon size={15} />
                    </button>
                  </div>
                </div>

                {/* Nacionalidade */}
                <div className="ca-field">
                  <span className="ca-label" id="country-label">
                    <NationalityIcon size={13} /> Nacionalidade
                  </span>
                  <div className="ca-seg" role="radiogroup" aria-labelledby="country-label">
                    {COUNTRIES.map((c) => (
                      <button
                        type="button"
                        key={c.id}
                        role="radio"
                        aria-checked={country === c.id}
                        aria-label={c.name}
                        title={c.name}
                        className={country === c.id ? 'is-selected' : ''}
                        onClick={() => setCountry(c.id)}
                      >
                        <CountryFlag countryId={c.id} />
                        <span>{c.id}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
              {ageError && (
                <p className="ca-msg is-error">
                  <AlertIcon size={13} /> {ageError}
                </p>
              )}
            </section>
          </div>

          <footer className="ca-footer">
            {submitError && (
              <p className="ca-msg is-error">
                <AlertIcon size={13} /> {submitError}
              </p>
            )}
            <button type="submit" className="gx-btn" disabled={!canSubmit}>
              <PlayIcon size={18} /> Iniciar carreira
            </button>
            <p className="ca-footnote">{canSubmit ? 'Você começa no nível 1. O resto é com você.' : missing}</p>
          </footer>
        </form>
      )}
    </AppShell>
  )
}
