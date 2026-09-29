import Pitch from '../components/Pitch'
import PlayerCard from '../components/PlayerCard'
import { POSITIONS } from '../data/positions'

export default function PositionStep({ value, onChange, onNext, onBack }) {
  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Posição em campo</h1>
        <p>Toque na escalação para escolher onde seu jogador vai atuar na carreira.</p>
      </div>

      <div className="step-body position-step-body">
        <PlayerCard appearance={value.appearance} nickname={value.nickname} countryId={value.country} />
        <Pitch
          positions={POSITIONS}
          selected={value.position}
          onSelect={(id) => onChange({ position: id })}
        />
      </div>

      <div className="step-footer">
        <button type="button" className="btn-secondary" onClick={onBack}>
          Voltar
        </button>
        <button type="button" className="btn-primary" disabled={!value.position} onClick={onNext}>
          Próximo
        </button>
      </div>
    </div>
  )
}
