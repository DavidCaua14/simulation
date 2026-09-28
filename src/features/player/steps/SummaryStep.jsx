import { useMemo } from 'react'
import { ShirtIcon, HashIcon, AlertIcon } from '../../../components/ui/icons'
import { POSITIONS } from '../data/positions'
import { getCountryById } from '../data/countries'
import { STARTING_LEVEL } from '../data/gameConstants'
import PlayerCard from '../components/PlayerCard'

export default function SummaryStep({ value, onChange, onBack, onSubmit, submitting, submitError }) {
  const jerseyError = useMemo(() => {
    const n = Number(value.jerseyNumber)
    if (!value.jerseyNumber) return 'Informe um número.'
    if (!Number.isInteger(n) || n < 1 || n > 99) return 'Escolha um número entre 1 e 99.'
    return ''
  }, [value.jerseyNumber])

  const canSubmit = !jerseyError && !submitting
  const positionLabel = POSITIONS.find((p) => p.id === value.position)?.label
  const countryName = getCountryById(value.country)?.name

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Últimos detalhes</h1>
        <p>Confira e escolha o número da camisa antes de começar a carreira.</p>
      </div>

      <div className="step-body">
        <PlayerCard
          appearance={value.appearance}
          nickname={value.nickname}
          countryId={value.country}
          positionLabel={`${positionLabel} · ${countryName} · Nível ${STARTING_LEVEL}`}
        />

        <div>
          <label className="field-label" htmlFor="jersey">
            <ShirtIcon /> Número da camisa
          </label>
          <div className="jersey-input-wrap">
            <HashIcon />
            <input
              id="jersey"
              className="input jersey-input"
              type="number"
              min={1}
              max={99}
              value={value.jerseyNumber}
              onChange={(e) => onChange({ jerseyNumber: e.target.value })}
            />
          </div>
          {jerseyError && (
            <p className="field-error">
              <AlertIcon /> {jerseyError}
            </p>
          )}
        </div>

        {submitError && (
          <p className="field-error">
            <AlertIcon /> {submitError}
          </p>
        )}
      </div>

      <div className="step-footer">
        <button type="button" className="btn-secondary" onClick={onBack} disabled={submitting}>
          Voltar
        </button>
        <button type="button" className="btn-primary" disabled={!canSubmit} onClick={onSubmit}>
          {submitting ? 'Criando...' : 'Começar carreira'}
        </button>
      </div>
    </div>
  )
}
