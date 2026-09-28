import { useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import StepDots from './components/StepDots'
import { ArrowLeftIcon } from '../../components/ui/icons'
import CharacterStep from './steps/CharacterStep'
import NicknameStep from './steps/NicknameStep'
import PositionStep from './steps/PositionStep'
import SummaryStep from './steps/SummaryStep'
import { createPlayer } from './playerService'
import { DEFAULT_APPEARANCE } from './data/characterOptions'
import './wizard.css'
import './player-visuals.css'

const STEPS = ['character', 'nickname', 'position', 'summary']

const INITIAL_FORM = {
  appearance: DEFAULT_APPEARANCE,
  nickname: '',
  country: 'BR',
  position: null,
  jerseyNumber: '10',
}

export default function CreatePlayerWizard({ onCreated }) {
  const [stepIndex, setStepIndex] = useState(0)
  const [form, setForm] = useState(INITIAL_FORM)
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState('')

  function updateForm(patch) {
    setForm((prev) => ({ ...prev, ...patch }))
  }

  function goNext() {
    setStepIndex((i) => Math.min(i + 1, STEPS.length - 1))
  }

  function goBack() {
    setStepIndex((i) => Math.max(i - 1, 0))
  }

  async function handleSubmit() {
    setSubmitError('')
    setSubmitting(true)
    try {
      const career = await createPlayer(form)
      onCreated?.(career)
    } catch (err) {
      setSubmitError(err.message || 'Não foi possível criar o jogador.')
    } finally {
      setSubmitting(false)
    }
  }

  const step = STEPS[stepIndex]

  return (
    <AppShell
      left={
        stepIndex > 0 ? (
          <button type="button" className="back-btn" onClick={goBack} aria-label="Voltar">
            <ArrowLeftIcon />
          </button>
        ) : null
      }
      center={<StepDots total={STEPS.length} current={stepIndex} />}
    >
      <LoadingOverlay show={submitting} label="Criando jogador..." />

      {step === 'character' && <CharacterStep value={form} onChange={updateForm} onNext={goNext} />}
      {step === 'nickname' && (
        <NicknameStep value={form} onChange={updateForm} onNext={goNext} onBack={goBack} />
      )}
      {step === 'position' && (
        <PositionStep value={form} onChange={updateForm} onNext={goNext} onBack={goBack} />
      )}
      {step === 'summary' && (
        <SummaryStep
          value={form}
          onChange={updateForm}
          onBack={goBack}
          onSubmit={handleSubmit}
          submitting={submitting}
          submitError={submitError}
        />
      )}
    </AppShell>
  )
}
